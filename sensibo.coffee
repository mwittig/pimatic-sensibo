
# #Sensibo plugin
module.exports = (env) ->

  Promise = env.require 'bluebird'
  types = env.require('decl-api').types
  _ = env.require 'lodash'
  commons = require('pimatic-plugin-commons')(env)
  rest = require('restler-promise')(Promise)
  url = require 'url'
  deviceConfigTemplates =
    "SensiboControl":
      name: "Sensibo"
      class: "SensiboControl"
    "SensiboFanControl":
      name: "Sensibo"
      class: "SensiboFanControl"
    "SensiboSensor":
      name: "Sensibo"
      class: "SensiboSensor"

  # ###SensiboPlugin class
  class SensiboPlugin extends env.plugins.Plugin

    # ####init()
    # The `init` function is called by the framework to ask your plugin to initialise.
    #
    # #####params:
    #  * `app` is the [express] instance the framework is using.
    #  * `framework` the framework itself
    #  * `config` the properties the user specified as config for your plugin in the `plugins`
    #     section of the config.json file
    #
    #
    init: (app, @framework, @config) =>
      # register devices
      deviceConfigDef = require("./device-config-schema")
      @base = commons.base @, 'SensiboPlugin'
      @baseUrl = @config.baseUrl
      @apiKey = @config.apiKey
      @options = {
        timeout: 1000 * @base.normalize @config.timeout ? @config.__proto__.timeout, 5, 86400
      }

      @framework.deviceManager.registerDeviceClass("SensiboSensor", {
        configDef: deviceConfigDef.SensiboSensor,
        createCallback: (config, lastState) =>
          return new SensiboSensor config, @, lastState
      })
      @framework.deviceManager.registerDeviceClass("SensiboControl", {
        configDef: deviceConfigDef.SensiboControl,
        createCallback: (config, lastState) =>
          return new SensiboControl config, @, lastState
      })
      @framework.deviceManager.registerDeviceClass("SensiboFanControl", {
        configDef: deviceConfigDef.SensiboFanControl,
        createCallback: (config, lastState) =>
          return new SensiboFanControl config, @, lastState
      })

      @framework.deviceManager.on('discover', (eventData) =>
        @framework.deviceManager.discoverMessage 'pimatic-sensibo', 'Searching for devices'

        @getPods().then( (podIds) =>
            id=null
            for podUid in podIds
              for own templateName of deviceConfigTemplates
                configTemplate = deviceConfigTemplates[templateName]
                id = @base.generateDeviceId @framework, "sensibo", id
                if id?
                  config = _.cloneDeep
                    class: configTemplate.class
                    id: id
                    name:  "#{configTemplate.name} #{id.substr(1 + id.indexOf '-')}"
                    podUid: podUid

                  @framework.deviceManager.discoveredDevice(
                    'pimatic-sensibo', "#{config.name}", config
                  )
        ).catch (errorMessage) =>
          @framework.deviceManager.discoverMessage 'pimatic-sensibo', errorMessage
      )

    getPods: () ->
      urlObject = url.parse @baseUrl, false, true
      urlObject.pathname = @addToUrlPath urlObject.pathname, "users/me/pods"
      urlObject.query =
        apiKey: "#{@apiKey}"
      @base.info url.format(urlObject).replace(/apiKey=[^&]+/i, "apiKey=XXX");

      rest.get(url.format(urlObject), @options).then((result) =>
        @base.info "response:", result.data
        data = result.data
        if data.status is 'success' and _.isArray data.result
          podIds = []
          for pod in data.result
            podIds.push pod.id || pod.name
          return Promise.resolve podIds
      ).catch (errorResult) =>
        @base.rejectWithErrorString Promise.reject,  errorResult.error ? errorResult, "Unable to query pods"

    addToUrlPath: (baseUrlString, path) ->
      return baseUrlString.replace(/\/$/,"") + '/' + path.replace(/^\//,"")

  class SensiboSensor extends env.devices.TemperatureSensor
    attributes:
      temperature:
        description: "Temperature"
        type: types.number
        unit: '°C'
        acronym: 'T'
      humidity:
        description: "Relative humidity"
        type: types.number
        unit: '%'
        acronym: 'RH'

    constructor: (@config, @plugin, @service) ->
      @debug = @plugin.config.debug ? false
      @base = commons.base @, @config.class unless @base?

      @base.debug "Device Initialization"
      @id = @config.id
      @name = @config.name
      @serviceUrlGet = @_createServiceUrl()
      @base.info @serviceUrlGet.replace(/apiKey=[^&]+/i, "apiKey=XXX");
      @options = @plugin.options
      intervalSeconds = (@config.interval or (@plugin.config.interval ? @plugin.config.__proto__.interval))
      @interval = 1000 * @base.normalize intervalSeconds, 10, 86400
      @_temperature = lastState?.temperature?.value or null
      @_humidity = lastState?.humidity?.value or null
      super()
      @_requestUpdate()

    destroy: () ->
      @base.cancelUpdate()
      super()

    _setHumidity: (value) ->
      @_humidity = value
      @emit 'humidity', value

    _createServiceUrl: ->
      urlObject = url.parse @plugin.baseUrl, false, true
      urlObject.pathname = @plugin.addToUrlPath urlObject.pathname, "pods/#{@config.podUid}/measurements"
      urlObject.query =
        apiKey: "#{@plugin.apiKey}"
        fields: "temperature,humidity"
      return url.format urlObject

    _requestUpdate: ->
      rest.get(@serviceUrlGet, @options).then((result) =>
        @base.info "response:", result.data
        data = result.data
        if data.status is 'success' and _.isArray data.result
          @_setHumidity data.result[0].humidity
          @_setTemperature data.result[0].temperature
      ).catch((errorResult) =>
        @base.error "Unable to get status values of device: ", errorResult.error ? errorResult
      ).finally () =>
        @base.scheduleUpdate @_requestUpdate, @interval

    getHumidity: -> Promise.resolve @_humidity

  class SensiboFanControl extends env.devices.ButtonsDevice

    constructor: (@config, @plugin, lastState) ->
      @id = @config.id
      @name = @config.name
      @base = commons.base @, @config.class
      for b in @config.buttons
        b.text = b.id unless b.text?
      @serviceUrlGet = @_createServiceUrl(
        limit:  1
        fields: "status,reason,acState,limit=10"
      )
      @serviceUrlPost = @_createServiceUrl()
      @options = @plugin.options
      super @config

    destroy: () ->
      super()

    _createServiceUrl: (queryParams) ->
      urlObject = url.parse @plugin.baseUrl, false, true
      urlObject.pathname = @plugin.addToUrlPath urlObject.pathname, "pods/#{@config.podUid}/acStates"
      urlObject.query =
        apiKey: "#{@plugin.apiKey}"
      if queryParams?
        for own k, v of queryParams
          urlObject.query[k] = v
      return url.format urlObject

    _getValues: ->
      new Promise (resolve, reject) =>
        rest.get(@serviceUrlGet, @options).then((result) =>
          @base.info "response:", result.data
          data = result.data
          if data.status is 'success' and _.isArray data.result
            @base.info "data:", data.result
            acState = data.result[0].acState
            resolve(acState)
          else
            reject new Error "Invalid response status: #{data.status}"
        ).catch (errorResult) =>
          reject errorResult.error ? errorResult

    buttonPressed: (buttonId) ->
      for b in @config.buttons
        if b.id is buttonId
          return @_getValues().then (acState) =>
            acState.fanLevel = b.id
            data =
              acState: acState
            rest.postJson(@serviceUrlPost, data, @options).then((result) =>
              @base.debug "post response:", result.data
              @_lastPressedButton = b.id
              @emit 'button', b.id
              Promise.resolve()
            ).catch((errorResult) =>
              @base.error "Unable to change status values of device: " + errorResult.error ? errorResult, errorResult.response || ''
              Promise.reject(errorResult.error ? errorResult)
            )

      throw new Error("No button with the id #{buttonId} found")

  class SensiboControl extends env.devices.PowerSwitch
    attributes:
      state:
        description: "Current State"
        type: types.boolean
        labels: ['on', 'off']
      targetTemperature:
        description: "Target Temperature"
        type: types.number
        unit: '°C'
        acronym: 'Tt'
      fanLevel:
        description: "The current fan level"
        type: types.string
        acronym: "fan"
      mode:
        description: "The current mode of operation"
        type: types.string
        acronym: "mode"

    # Initialize device by reading entity definition from middleware
    constructor: (@config, @plugin, @service) ->
      @debug = @plugin.config.debug ? false
      @base = commons.base @, @config.class unless @base?

      @base.debug "Device Initialization"
      @id = @config.id
      @name = @config.name
      @serviceUrlGet = @_createServiceUrl(
        limit:  1
        fields: "status,reason,acState,limit=10"
      )
      @serviceUrlPost = @_createServiceUrl()
      @base.debug @serviceUrlGet.replace(/apiKey=[^&]+/i, "apiKey=XXX");
      @options = @plugin.options
      intervalSeconds = (@config.interval or (@plugin.config.interval ? @plugin.config.__proto__.interval))
      @interval = 1000 * @base.normalize intervalSeconds, 10, 86400
      @_fanLevel = lastState?.fanLevel?.value or 'low'
      @_mode = lastState?.mode?.value or 'fan'
      @_targetTemperature = lastState?.targetTemperature?.value or 20.0
      super()
      @_requestUpdate()

    destroy: () ->
      @base.cancelUpdate()
      super()

    _createServiceUrl: (queryParams) ->
      urlObject = url.parse @plugin.baseUrl, false, true
      urlObject.pathname = @plugin.addToUrlPath urlObject.pathname, "pods/#{@config.podUid}/acStates"
      urlObject.query =
        apiKey: "#{@plugin.apiKey}"
      if queryParams?
        for own k, v of queryParams
          urlObject.query[k] = v
      return url.format urlObject

    _getValues: ->
      new Promise (resolve, reject) =>
        rest.get(@serviceUrlGet, @options).then((result) =>
          @base.debug "response:", result.data
          data = result.data
          if data.status is 'success' and _.isArray data.result
            @base.debug "data:", data.result
            acState = data.result[0].acState
            @base.setAttribute "fanLevel", acState.fanLevel
            @base.setAttribute "mode", acState.mode
            @base.setAttribute "targetTemperature", acState.targetTemperature
            @_setState acState.on
            resolve()
          else
            reject new Error "Invalid response status: #{data.status}"
        ).catch (errorResult) =>
          reject errorResult.error ? errorResult

    _requestUpdate: ->
      @_getValues().catch((error) =>
        @base.error "Unable to get status values of device: " + error
      ).finally () =>
        @base.scheduleUpdate @_requestUpdate, @interval

    getFanLevel: -> Promise.resolve @_fanLevel
    getMode: -> Promise.resolve @_mode
    getTargetTemperature: -> Promise.resolve @_targetTemperature
    changeStateTo: (newState) ->
      @_getValues().then =>
        data =
          acState:
            on: newState
            mode: @_mode
            fanLevel: @_fanLevel
            targetTemperature: @_targetTemperature
        rest.postJson(@serviceUrlPost, data, @options).then((result) =>
          @base.debug "post response:", result.data
          @_setState newState
          Promise.resolve()
        ).catch((errorResult) =>
          @base.error "Unable to change status values of device: " + errorResult.error ? errorResult, errorResult.response || ''
          Promise.reject(errorResult.error ? errorResult)
        )

  # ###Finally
  # Create a instance of my plugin
  myPlugin = new SensiboPlugin()
  # and return it to the framework.
  return myPlugin

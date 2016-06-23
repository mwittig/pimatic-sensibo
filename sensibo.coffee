
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
                    name:  "#{configTemplate.name} #{id}"
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

      rest.get(url.format(urlObject), @options).then((result) =>
        @base.debug "response:", result.data
        podIds = []
        for pod in result.data
          podIds.push pod.id || pod.name
        return Promise.resolve podIds
      ).catch (errorResult) =>
        @base.rejectWithErrorString Promise.reject,  errorResult.error, "Unable to query pods"

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

    _requestUpdate: ->
      urlObject = url.parse @plugin.baseUrl, false, true
      urlObject.pathname = @plugin.addToUrlPath urlObject.pathname, "pods/#{@plugin.apiKey}/measurements"

      rest.get(url.format(urlObject), @options).then((result) =>
        @base.info "response:", result.data
        json = JSON.parse result.data
        @_setHumidity +json[0].humidity
        @_setTemperature +json[0].temperature
      ).catch((error) =>
        @base.error "Unable to get status values of device: " + error.toString()
      ).finally () =>
        @base.scheduleUpdate @_requestUpdate, @interval

    getHumidity: -> Promise.resolve @_humidity

  class SensiboControl extends env.devices.PowerSwitch
    attributes:
      state:
        description: "Current State"
        type: types.boolean
        labels: ['on', 'off']
      fanLevel:
        description: "The current fan level"
        type: types.string
      mode:
        description: "The current mode of operation"
        type: types.string

    # Initialize device by reading entity definition from middleware
    constructor: (@config, @plugin, @service) ->
      @debug = @plugin.config.debug ? false
      @base = commons.base @, @config.class unless @base?

      @base.debug "Device Initialization"
      @id = @config.id
      @name = @config.name
      @_fanLevel = lastState?.fanLevel?.value or 'low'
      @_mode = lastState?.mode?.value or 'fan'
      @_requestUpdate()
      super()

    destroy: () ->
      @base.cancelUpdate()
      super()

    _requestUpdate: ->
      urlObject = url.parse @plugin.baseUrl, false, true
      urlObject.pathname = @plugin.addToUrlPath urlObject.pathname, "pods/#{@plugin.apiKey}/acStates"

      rest.get(url.format(urlObject), @options).then((result) =>
        @base.info "response:", result.data
      ).catch((error) =>
        @base.error "Unable to get status values of device: " + error.toString()
      ).finally () =>
        @base.scheduleUpdate @_requestUpdate, @interval

    getFanLevel: -> Promise.resolve @_fanLevel
    getMode: -> Promise.resolve @_mode


  # ###Finally
  # Create a instance of my plugin
  myPlugin = new SensiboPlugin()
  # and return it to the framework.
  return myPlugin
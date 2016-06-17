
# #Sensibo plugin
module.exports = (env) ->

  Promise = env.require 'bluebird'
  types = env.require('decl-api').types
  _ = env.require 'lodash'
  commons = require('pimatic-plugin-commons')(env)
  rest = require('restler-promise')(Promise)
  url = require 'url'
  deviceConfigTemplates =
    "SensiboDevice":
      name: "Sensibo"
      class: "SensiboDevice"

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

      @framework.deviceManager.registerDeviceClass("SensiboDevice", {
        configDef: deviceConfigDef.SensiboDevice,
        createCallback: (config, lastState) =>
          return new SensiboDevice config, @, lastState
      })

      @framework.deviceManager.on('discover', (eventData) =>
        @framework.deviceManager.discoverMessage 'pimatic-sensibo', 'Searching for devices'

        @getPods().then( (podIds) =>
            for podUid in podIds
              for own templateName of deviceConfigTemplates
                configTemplate = deviceConfigTemplates[templateName]
                id = @generateDeviceId "#{configTemplate.name.toLowerCase().replace(/\s/g, '-')}"
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

    generateDeviceId: (prefix) ->
      for x in [1...1000]
        result = "#{prefix}-#{x}"
        matched = @framework.deviceManager.devicesConfig.some (element, iterator) ->
          element.id is result
        return result if not matched

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

  class SensiboDevice extends env.devices.PowerSwitch
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
      super()

    destroy: () ->
      super()

    getFanLevel: -> Promise.resolve @_fanLevel
    getMode: -> Promise.resolve @_mode


  # ###Finally
  # Create a instance of my plugin
  myPlugin = new SensiboPlugin()
  # and return it to the framework.
  return myPlugin

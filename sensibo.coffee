# #Sensibo plugin
module.exports = (env) ->

  Promise = env.require 'bluebird'
  _ = env.require 'lodash'
  commons = require('pimatic-plugin-commons')(env)

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

      @framework.deviceManager.registerDeviceClass("SensiboDevice", {
        configDef: deviceConfigDef.SensiboDevice,
        createCallback: (config, lastState) =>
          return new SensiboDevice config, @, lastState
      })


  class SensiboDevice extends env.devices.Device
    # Initialize device by reading entity definition from middleware
    constructor: (@config, @plugin, @service) ->
      @debug = @plugin.config.debug ? false
      @base = commons.base @, @config.class unless @base?

      @base.debug("Device Initialization")
      @id = @config.id
      @name = @config.name

      super()

    destroy: () ->
      super()




  # ###Finally
  # Create a instance of my plugin
  myPlugin = new SensiboPlugin
  # and return it to the framework.
  return myPlugin

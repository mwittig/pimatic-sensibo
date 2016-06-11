module.exports = {
  title: "pimatic-sensibo plugin config options"
  type: "object"
  properties:
    apiKey:
      description: "Sensibo API key to be obtained from https://home.sensibo.com/me/api"
      type: "string"
    interval:
      description: "Polling interval for switch state in seconds, value range [10-86400] or 0 to use device setting"
      type: "number"
      default: 60
    debug:
      description: "Debug mode. Writes debug message to the pimatic log"
      type: "boolean"
      default: false
}
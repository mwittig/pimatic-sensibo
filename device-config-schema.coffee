module.exports = {
  title: "pimatic-sensibo device config schemas"
  SensiboControl: {
    title: "Sensibo AC Control"
    description: ""
    type: "object"
    properties:
      podUid:
        description: "The unique id of the Pod"
        type: "string"
  }
  SensiboSensor: {
    title: "Sensibo AC Temperature/Humidity Sensor"
    description: ""
    type: "object"
    properties:
      podUid:
        description: "The unique id of the Pod"
        type: "string"
  }
}
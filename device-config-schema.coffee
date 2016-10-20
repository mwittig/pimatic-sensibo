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
  SensiboFanControl: {
    title: "Sensibo Fan Control"
    description: "Sensibo Control for the fan mode"
    type: "object"
    properties:
      podUid:
        description: "The unique id of the Pod"
        type: "string"
      buttons:
        description: "The fan level control buttons"
        type: "array"
        options:
          hidden: yes
        default: [
          {
            id: "low"
          }
          {
            id: "medium"
          }
          {
            id: "high"
          }
          {
            id: "auto"
          }
        ]
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
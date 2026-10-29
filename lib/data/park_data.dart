/// Static park content for the demo.
class Ride {
  const Ride(this.name, this.wait, this.kind, {this.x = 0, this.z = 0});
  final String name;
  final int wait;
  final String kind;
  // position on the 3D park map
  final double x;
  final double z;
}

const rides = [
  Ride('Sky Coaster', 15, 'RIDE', x: -3.4, z: 2.6),
  Ride('River Run', 15, 'RIDE', x: 3.3, z: 2.4),
  Ride('Star Swing', 5, 'RIDE', x: -3.0, z: -0.5),
  Ride('Moon Drop', 35, 'RIDE', x: 3.4, z: -0.7),
  Ride('Tidal Twist', 5, 'RIDE', x: 0.4, z: 4.4),
  Ride('Comet Carousel', 10, 'RIDE', x: 0.1, z: 2.5),
];

class Place {
  const Place(this.name, this.status, this.kind);
  final String name;
  final String status;
  final String kind;
}

const dining = [
  Place('Harbor Grill', 'Open', 'FOOD'),
  Place('Lantern Café', 'Open', 'FOOD'),
  Place('Starlight Treats', 'Open', 'FOOD'),
  Place('Comet Cones', 'Closes 10 PM', 'FOOD'),
];

const shows = [
  Place('Fireworks over the lagoon', '9:15 PM', 'SHOW'),
  Place('Lantern Parade', '8:00 PM', 'SHOW'),
  Place('Moonlight Melodies', '7:30 PM', 'SHOW'),
];

class ConnectedDevice {
  String? name;
  String? address;

  ConnectedDevice({this.name, this.address});

  factory ConnectedDevice.fromJson(Map<String, dynamic> json) {
    return ConnectedDevice(
      name: json['name'],
      address: json['address'],
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
      };
}

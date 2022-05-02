class ConnectedDevice {
  String? label;
  String? address;

  ConnectedDevice({this.label, this.address});

  factory ConnectedDevice.fromJson(Map<String, dynamic> json) {
    return ConnectedDevice(
      label: json['label'],
      address: json['address'],
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'address': address,
      };
}

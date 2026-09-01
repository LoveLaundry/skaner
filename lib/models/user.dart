class User {
  final int id;
  final String userName;
  final String authId;
  final String? email;
  final String roleId;
  final String status;
  final String? employeeId;
  final String? mobileNumber;

  User({
    required this.id,
    required this.userName,
    required this.authId,
    this.email,
    required this.roleId,
    required this.status,
    this.employeeId,
    this.mobileNumber,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? 0,
      userName: json['user_name'] ?? '',
      authId: json['auth_id'] ?? '',
      email: json['email'],
      roleId: json['role_id'] ?? '',
      status: json['status'] ?? '',
      employeeId: json['employee_id'],
      mobileNumber: json['mobile_number'],
    );
  }

  bool get isAdmin => roleId == 'ADMIN';
  bool get isManager => roleId == 'MANAGER';
  bool get isStaff => roleId == 'STAFF';
  bool get canScan => true; // all roles can scan
  bool get canWrite => isAdmin || isManager;
}

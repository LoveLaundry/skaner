import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/linen.dart';

class LinenService {
  final String token;
  LinenService({required this.token});

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Future<LinenItem?> lookupByCode(String code) async {
    try {
      final response = await http.get(
        Uri.parse(ApiConfig.linenByCode(code)),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        return LinenItem.fromJson(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<String?> performScanAction({
    required String docId,
    required String action,
    String? location,
    String? user,
    String? notes,
  }) async {
    try {
      final body = <String, dynamic>{'action': action};
      if (location != null) body['location'] = location;
      if (user != null) body['user'] = user;
      if (notes != null) body['notes'] = notes;

      final response = await http.post(
        Uri.parse(ApiConfig.linenScan(docId)),
        headers: _headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        return null; // success
      } else {
        final data = jsonDecode(response.body);
        return data['detail'] ?? 'Action failed';
      }
    } catch (e) {
      return 'Connection error: $e';
    }
  }

  Future<List<Map<String, dynamic>>> getEvents(String docId) async {
    try {
      final response = await http.get(
        Uri.parse(ApiConfig.linenEvents(docId)),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}

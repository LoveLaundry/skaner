import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/garment_tag.dart';

class GarmentService {
  Future<GarmentTag?> lookupByCode(String code) async {
    try {
      final response = await http.get(
        Uri.parse(ApiConfig.tagByCode(code)),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        return GarmentTag.fromJson(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<GarmentTag?> getTracking(String code) async {
    try {
      final response = await http.get(
        Uri.parse(ApiConfig.tagTracking(code)),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        return GarmentTag.fromJson(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

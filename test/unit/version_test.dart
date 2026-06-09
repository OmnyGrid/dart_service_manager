@Tags(['version'])
library;

import 'dart:io';

import 'package:dart_service_manager/dart_service_manager.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('dartServiceManagerVersion matches pubspec.yaml', () {
    final pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    expect(dartServiceManagerVersion, pubspec['version']);
  });
}

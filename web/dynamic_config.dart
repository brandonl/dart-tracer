library dart_tracer_config;

import 'dart:async';
import 'package:yaml/yaml.dart' as YAML;

import 'package:dart_config/config.dart';
import 'package:dart_config/loaders/config_loader_httprequest.dart';
import 'dart:mirrors' as mirrors;

/// Based on https://github.com/Digitalxero/dart-dynamic_object
@proxy
class DynamicConfig implements Map {
  final Map<String, Object> _configData;

  DynamicConfig( this._configData );

  @override
  dynamic noSuchMethod( final Invocation mirror ) {
    final property = _symbolToString( mirror.memberName );

    if( mirror.isGetter ) {
      var val = _configData[property];
      if( val is Map ) return new DynamicConfig( val );
      else if( val is List && val[0] is Map ) {
        return val.map( (m) => new DynamicConfig(m) );
      }
      else return val;
    }
    else if( mirror.isSetter ) {
      throw new UnsupportedError( "Read Only! Editing a DynamicConfig is not allowed." );
    }
    else if( mirror.isMethod ) {
      throw new UnsupportedError( "Config entries are not invocable" );
    }

    super.noSuchMethod(mirror);
  }

  String _symbolToString( value ) {
    if( value is Symbol ) return mirrors.MirrorSystem.getName(value);
    else return value.toString();
  }

  void forEach( void f(String, Object) ) => _configData.forEach(f);

  Iterable get keys => _configData.keys;

  Object operator []( final String key ) => _configData[_symbolToString(key)];
}

class DynamicYamlConfigParser implements ConfigParser {

  Future<Map> parse(String configText) {
    final completer = new Completer<Map>();

    final map = YAML.loadYaml(configText);
    completer.complete( new DynamicConfig( map ) );

    return completer.future;
  }
}

Future<Map> loadConfig([String filename="config.yaml"]) {
  final config = new Config(filename,
      new ConfigHttpRequestLoader(),
      new DynamicYamlConfigParser());

  return config.readConfig();
}
library dart_tracer_common;

import 'dart:html';
import 'package:vector_math/vector_math.dart';
import 'dart:math' as math;

final double EPSILON = 0.005;
final double INF = double.INFINITY;

intColor( num d ) =>((d > 1 ? 1 : d) * 255).toInt();

class Ray {
  final Vector3 origin, dir;
  Ray( this.origin, this.dir );
}

class Sphere {
  final Vector3 center;
  final num radius;
  final Vector3 _specularColor;
  final num specularConstant;
  final Vector3 _diffuseColor;
  final num diffuseConstant;
  final Vector3 _ambientColor;
  final num ambientConstant;
  final num shininess;

  Sphere( this.center,
      this.radius,
      this._specularColor,
      this.specularConstant,
      this._diffuseColor,
      this.diffuseConstant,
      this._ambientColor,
      this.ambientConstant,
      this.shininess );

  Vector3 normal( final Vector3 pos ) => ( pos - this.center ).normalize();

  double intersect( final Ray ray ) {
    var eyeToCenter = center - ray.origin;
    var v = eyeToCenter.dot( ray.dir );
    var eoDot = eyeToCenter.dot( eyeToCenter );
    var discriminant = (radius * radius) - eoDot + (v * v);
    if( discriminant < 0 ) return INF;
    else return v - math.sqrt( discriminant );
  }
  Vector3 get specularColor => _specularColor;
  Vector3 get diffuseColor => _diffuseColor;
  Vector3 get ambientColor => _ambientColor;
}

class Intersection {
  final Ray ray;
  final double distance;
  final Sphere intersected;

  Intersection( this.ray, this.distance, this.intersected );
}

// TODO Create color class rather than lazily using Vec3
class Colors {
  static Vector3 of( double r, double g, double b ) => new Vector3( r, g, b );
  static final Vector3 GRAY = new Vector3( 0.5, 0.5, 0.5 );
  static final Vector3 WHITE = new Vector3( 1.0, 1.0, 1.0 );
  static final Vector3 RED = new Vector3( 1.0, 0.0, 0.0 );
  static final Vector3 BLACK = new Vector3( 0.0, 0.0, 0.0 );
}

class Camera {
  static final Vector3 UP = new Vector3( 0.0, 1.0, 0.0 );

  final int fov;
  Vector3 pos, forward, right, up;
  Camera( int fov, final Vector3 pos, final Vector3 lookingAt )
      : fov = fov,
        pos = pos,
        forward = ( lookingAt - pos ).normalize() {
    right = UP.cross(forward).normalize();
    up = forward.cross(right).normalize();
  }
}

class Light {
  final Vector3 pos;
  final Vector3 color;
  Light(this.pos, this.color);
}

class World {
  final Camera camera;
  final Iterable<Light> lights;
  final Iterable<Sphere> spheres;
  final CanvasElement device;

  World(this.camera, this.lights, this.spheres, this.device);
}
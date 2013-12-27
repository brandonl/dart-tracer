library dart_tracer;

import 'dart:html';
import 'dart:async';
import 'package:vector_math/vector_math.dart';
import 'dart:math' as math;
import "common.dart";
import "dynamic_config.dart";

final Vector3 BG = Colors.WHITE;
final MAX_DEPTH = 4;

main() {
  loadConfig( "config/app.yaml" )
    .then( _load )
    .then( _update );
}

World _load( final DynamicConfig conf ) {
  final cc = conf.canvas;
  final w = cc.width;
  final h = cc.height;

  final CanvasElement c = querySelector( '#c' ) as CanvasElement
      ..height = h
      ..width = w
      ..style.cssText = 'width: $w px; height: $h px';

  final worldc = conf.world;
  final camc = worldc.camera;
  final lightsc = worldc.lights;
  final spheresc =  worldc.spheres;

  final Camera cam = new Camera(
      camc.fov,
      new Vector3( camc.pos.x, camc.pos.y, camc.pos.z ),
      new Vector3( camc.lookingAt.x, camc.lookingAt.y, camc.lookingAt.z ) );

  final Iterable lights = lightsc.map( (lc) {
      final colorc = lc.color;
      return new Light( new Vector3( lc.x, lc.y, lc.z ),
          Colors.of( colorc.r, colorc.g, colorc.b) );
    } );

  final Iterable spheres = spheresc.map( (sc) {
      return new Sphere( new Vector3( sc.center.x, sc.center.y, sc.center.z ),
          sc.radius,
          Colors.of( sc.specularColor.r, sc.specularColor.g, sc.specularColor.b ),
          sc.specularConstant,
          Colors.of( sc.diffuseColor.r, sc.diffuseColor.g, sc.diffuseColor.b ),
          sc.diffuseConstant,
          Colors.of( sc.ambientColor.r, sc.ambientColor.g, sc.ambientColor.b ),
          sc.ambientConstant,
          sc.shininess);
    } );
  return new World(cam, lights, spheres.toList(), c);
}


_update( final World world ) {
  bool playing = true;

  final device = world.device;
  final cam = world.camera;
  final lights = world.lights;
  final w = device.width;
  final h = device.height;

  final CanvasRenderingContext2D ctx = device.getContext( '2d' );
  final ImageData data = ctx.getImageData(0, 0, w, h);

  ///                  (1,1)
  ///    -------------
  ///   |             |
  ///   |             |
  ///   |    (0,0)    |
  ///   |             |
  ///   |             |
  ///   |_____________|
  /// (-1,0)
  ///
  /// This function converts screen space to world space. It takes a pixel loc
  /// and clamps it to the domain/range [-1.0, 1.0].
  ///
  /// Then using the cameras displacement vectors it will adjust those vectors
  /// to point towards the pixel in world space.
  ///
  final findWorldSpaceDir = (x, y, Camera camera) {
    final dx = (x) => (x - (w / 2.0)) / w;
    final dy = (y) => - (y - (h / 2.0)) / h;
    return ( camera.forward
            + camera.right * dx(x)
            + camera.up    * dy(y) ).normalize();
  };

  /// Loop through all pixels in screen space, converting to world space and
  /// shooting a ray toward each originating from the camera's position.
  /// From this [eyeRay] 'trace' it.
  tick() {

    for( var x = 0; x < w; x++ ) {
        for( var y = 0; y < h; y++ ) {
            final rayDir = findWorldSpaceDir( x, y, cam );
            final eyeRay = new Ray( cam.pos, rayDir );
            final color = _trace( eyeRay, world );

            final index = (x + y * w ) * 4;
            data.data[index + 0] = intColor( color.r );
            data.data[index + 1] = intColor( color.g );
            data.data[index + 2] = intColor( color.b );
            data.data[index + 3] = 255;
        }
    }
    ctx.putImageData( data, 0, 0 );
  }
  tick();
}

Intersection _findNearestIntersection( final Ray ray, final World world ) {
  return world.spheres.fold( new Intersection( ray, INF, null ), (acc, e) {
    // Calculation depends on the object we hit.
    final dist = e.intersect(ray);
    if( dist < acc.distance ) return new Intersection( ray, dist, e );
    else return acc;
  });
}

/// Given a [ray] find the nearest intersection point with some object
/// in the nominated [world]. Calculate the color of the point the [ray] intersects.
/// If it hits nothing the color is that of the background.
/// Otherwise, find the normal of the object's surface that the ray intersected,
/// the reflected ray from the intersection point outwards, and calculate the color
/// of the intersected point.
/// Note: There is a base case checking for a [MAX_DEPTH] due to reflection rays also
/// being traced recursively.
Vector3 _trace( final Ray ray, final World world, [final int depth = 0] ) {
  if( depth <= MAX_DEPTH ) {
    final intersection = _findNearestIntersection( ray, world );
    if( identical( intersection.distance, INF ) ) return BG;
    else {
      // Move the ray's origin (in the non-reflective case it's the camera's position)
      // by the rays direction scaled by the distance to the intersection, i.e.
      // find the point we hit.
      final intersectionPt = ray.origin + ( ray.dir * ( intersection.distance ) );
      final hit = intersection.intersected;
      // Calculation depends on the object we hit, in general it would be a polygon
      // and performed use barycentric coordinates.
      final surfaceNormal = hit.normal( intersectionPt );
      return _findColor( hit, intersectionPt, surfaceNormal, ray.dir, world, depth ) +
          _findReflectedColor( hit, intersectionPt, surfaceNormal, ray.dir, world, depth );
    }
  }
  else return Colors.BLACK;
}

/// Calulates the RGB color at a particular point intersection of on some object. It currently
/// uses the Phong shading model:
/// L = Towards Light (normalized)
/// N = Surface normal (normalized)
/// I = Intensity (RGB) i.e. Intensity = Light color
/// M = Material (RGB)
/// V = To Viewer
/// R = Reflected vector, reflected L about N
///    V    N     I
///  R  \   |    /
///    \ \  |  /
///      \\ |/
///  ----------------
///  obj surface
///
/// Intensity = Ispec + Idiffuse + Iambient, where
/// Iambient = Mamb x Gamb (Gamb is the scenes global ambient constant).
///            Represents global light bouncing about the scene, no light sources are required in the calculation
/// Idiffuse = (N . L) * Ldiff * Iintensity x Mdiff
///            Diffuse lighting obey's Lambert's law: the intensity of the reflect light is proportional to the cosine
///            of the angle between surface noaml and light rays. Models light rays that are reflected in random directions
///            due to a materials roughness.
/// Ispecular = (V . R)^Mshininess * Ispec * Iintensity x Mspec
///            Models the direct reflection of light rays to the eye. Mshininess (glossiness, aka Phong exponent) controls
///            how wide the 'hotspot' is (e.g. how wide the shiny reflection area is).
Vector3 _findColor(final Sphere hit,
               final Vector3 intersectionPt,
               final Vector3 surfaceNormal,
               final Vector3 eyeRay,
               final World world,
               int depth ) {

  bool _isLightVisible( final Vector3 origin,
                        final World world,
                        final Light light) {
  final intersection = _findNearestIntersection(
    new Ray( origin, ( origin - light.pos ).normalize() ),
      world );
    return intersection.distance > -EPSILON;
  }

  // Calculate diffuse (lambert) and specular component from all lights.
  final preAmbient = world.lights.fold( new Vector3.zero(), (acc, light) {

    if( _isLightVisible( intersectionPt, world, light ) ) {
      final lightColor = light.color;
      final toLightVec = ( light.pos - intersectionPt ).normalize();
      acc +=  _specularComponent(hit, toLightVec, eyeRay, surfaceNormal, lightColor) +
              _diffuseComponent(hit, toLightVec, surfaceNormal, lightColor);

    }
    return acc;
  });
  return preAmbient + _ambientComponent(hit);
}

/// Reflect the eye ray of the intersected object, via its surface normal, and reverse this vector so that it
/// points away from the object. Use this as a new 'eye ray' to ray trace.
Vector3 _findReflectedColor( final Sphere hit,
                             final Vector3 intersectionPt,
                             final Vector3 surfaceNormal,
                             final Vector3 eyeRay,
                             final World world,
                             final int depth ) {
  final reflectedRay = new Ray( intersectionPt, eyeRay.reflected(surfaceNormal).scaled(-1.0) );
  return _trace( reflectedRay, world, depth + 1 ) * hit.specularConstant;
}

/// See [_findColor].
Vector3 _diffuseComponent( final Sphere obj,
                           final Vector3 toLightVec,
                           final Vector3 normal,
                           final Vector3 lightColor ) {
  final illum = toLightVec.dot( normal );
  // If > 0 then theta (angle between a and b in a dot b) between 0 and 90 deg.
  // If <= 0 theta between 90 and 180
  if(illum > 0 ) {
    return new Vector3.copy( obj.diffuseColor ).multiply( lightColor ) * illum * obj.diffuseConstant;
  }
  else return Colors.BLACK;
}

/// See [_findColor].
Vector3 _specularComponent( final Sphere obj,
                            final Vector3 toLightVec,
                            final Vector3 eyeRay,
                            final Vector3 surfaceNormal,
                            final Vector3 lightColor ) {
  final reflected = toLightVec.reflected(surfaceNormal);
  final spec = eyeRay.dot( reflected.normalize() );
  // If > 0 then theta (angle between a and b in a dot b) between 0 and 90 deg.
  // If <= 0 theta between 90 and 180
  if( spec > 0 ) {
    return new Vector3.copy( obj.specularColor ).multiply( lightColor ) * obj.specularConstant * ( math.pow( spec, obj.shininess ) );
  }
  else return Colors.BLACK;
}

/// See [_findColor].
Vector3 _ambientComponent( final Sphere obj ) {
  return obj.ambientColor * obj.ambientConstant;
}
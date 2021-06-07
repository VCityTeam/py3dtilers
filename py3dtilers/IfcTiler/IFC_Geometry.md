# Understanding the object placement and geometry in IFC

## The object placement

Each geometry is described in a local space.

An [IfcLocalPlacement](https://standards.buildingsmart.org/IFC/RELEASE/IFC2x3/TC1/HTML/ifcgeometricconstraintresource/lexical/ifclocalplacement.htm) field describes the object relative placement to another *ifc product*.
If this field is empty, it means that the object placement uses the world coordinates.
If not, the relative placement to another object is described with two fields :

* one, [IfcObjectPlacement](https://standards.buildingsmart.org/IFC/RELEASE/IFC2x3/TC1/HTML/ifcgeometricconstraintresource/lexical/ifcobjectplacement.htm) describes the offset of the object to its parent, using a Vec3
* the other, [IfcAxis2Placement3D](https://standards.buildingsmart.org/IFC/RELEASE/IFC2x3/TC1/HTML/ifcgeometryresource/lexical/ifcaxis2placement3d.htm) describes two Vec3 corresponding the Z-axis (named Axis) and X-axis (named RefDirection) that allows to transform the object space in the parent space with the construction of the tranformation matrix with the function [IfcBuildAxes](https://standards.buildingsmart.org/IFC/RELEASE/IFC2x3/FINAL/HTML/ifcgeometryresource/lexical/ifcbuildaxes.htm) and [IfcFirstProjAxis](https://standards.buildingsmart.org/IFC/RELEASE/IFC2x3/FINAL/HTML/ifcgeometryresource/lexical/ifcfirstprojaxis.htm)

Each object should be place relatively to its parent.The only exception is the [IfcSite](https://standards.buildingsmart.org/IFC/RELEASE/IFC2x/ADD1/HTML/ifcproductextension/lexical/ifcsite.html) that should be placed within the world coordinates (eventually using a projection system).
Following the Ifc hierarchy, an object (IfcProduct) is placed in an IfcSpace, which is placed in an IfcStorey, which is placed in an IfcBuilding, which is placed in the IfcSite.
To find the relative position of an object to the origin (which is the IfcSite position) :

* find the relative position and transformation matrix for each parents of the object, until reaching the IfcSite

  ```python
  v should be a vec3, describing a position
  IfcBuildAxes(p) should produce a 3x3 matrix
  IfcObjectPlacement should be a vec3
  For each v in Vertex :
    For each p in Parents :
      v = multiply(v, IfcBuildAxes(p))
      v = add(v,p.IfcOjbectPlacement)
  ```

---

## The object geometry

- Each object can have multiple representations.
For example, a door can contain two geometry, one for the panel, the other one for the handle.

- It exists multiple type of representation : [IfcShapeRepresentation](https://standards.buildingsmart.org/IFC/RELEASE/IFC4/ADD2/HTML/schema/ifcrepresentationresource/lexical/ifcshaperepresentation.htm)
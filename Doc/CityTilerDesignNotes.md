# CityTiler design notes

The CityTiler script requires some understanding of the 3DCity-DB data model.
CityTiler currently only extracts the surface data for LoD2 buildings.
As a consequence (in a form of disclaimer) the method used by CityTiler may not work for every CityGML file, since there seems to be multiple ways for storing the same information.
3DCity-DB data is organized in the following way:

* the `building` table contains the "abstract" building subdivisions (building, building part)
* the `thematic_surface` table contains all the surface objects (wall, roof, floor), with links to the building object it belongs to and the geometric data in the `surface_geometry` table
* The `surface_geometry` table contains the geometry of the surface (and volumic for some reason) objects
* The `cityobject` table contains both the `thematic_surface` and the building objects

The CityTiler "algorithm" goes

* starting with the ids of the building we want to export, we select the abstract building objects that are descendant of the buildings.

  ```sql
  cursor.execute("SELECT building.id, building_parent_id, cityobject.gmlid, cityobject.objectclass_id FROM building
  JOIN cityobject ON building.id=cityobject.id WHERE building_root_id IN %s", (buildingIds,))
  ```

* Then, using the ids of all the abstract building parts, we select all the surface objects that are linked to these building parts. Since the geometric surfaces are also organised in a hierarchy (to each thematic surface corresponds a tree of surface geometries), we need to group them into a single geometry.
  
  ```sql
  cursor.execute("SELECT cityobject.id, cityobject.gmlid, thematic_surface.building_id,
  thematic_surface.objectclass_id, ST_AsBinary(ST_Multi(ST_Collect(ST_Translate(
  surface_geometry.geometry, -1845500, -5176100, 0)))) FROM surface_geometry
  JOIN thematic_surface ON surface_geometry.root_id=thematic_surface.lod2_multi_surface_id
  JOIN cityobject ON thematic_surface.id=cityobject.id WHERE thematic_surface.building_id
  IN %s GROUP BY surface_geometry.root_id, cityobject.id, cityobject.gmlid,
  thematic_surface.building_id, thematic_surface.objectclass_id", (subBuildingIds,))
  ```

  In more readable pseudo-code: 
  
  ```sql
  SELECT id, gmlid, building_id, objectclass_id, group(geometry) FROM surface_geometry 
  JOIN thematic_surface ON root_id=lod2_multi_surface_id # lod2_multi_surface_id only points on the root of the geometry tree
  JOIN cityobject ON id
  WHERE building_id IN [abstract building parts list]
  GROUP BY root_id
  ```

  Once we have all this information, we just need to put it in a batch table using py3dtiles.

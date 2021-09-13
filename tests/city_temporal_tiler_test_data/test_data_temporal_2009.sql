--
-- PostgreSQL database dump
--

-- Dumped from database version 10.17
-- Dumped by pg_dump version 10.17

-- Started on 2021-09-13 14:09:53

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 8 (class 2615 OID 416240)
-- Name: citydb; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA citydb;


ALTER SCHEMA citydb OWNER TO postgres;

--
-- TOC entry 7 (class 2615 OID 418753)
-- Name: citydb_pkg; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA citydb_pkg;


ALTER SCHEMA citydb_pkg OWNER TO postgres;

--
-- TOC entry 1 (class 3079 OID 12924)
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- TOC entry 5613 (class 0 OID 0)
-- Dependencies: 1
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- TOC entry 3 (class 3079 OID 414752)
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- TOC entry 5614 (class 0 OID 0)
-- Dependencies: 3
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


--
-- TOC entry 2 (class 3079 OID 415680)
-- Name: postgis_raster; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS postgis_raster WITH SCHEMA public;


--
-- TOC entry 5615 (class 0 OID 0)
-- Dependencies: 2
-- Name: EXTENSION postgis_raster; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION postgis_raster IS 'PostGIS raster types and functions';


--
-- TOC entry 2306 (class 1247 OID 418756)
-- Name: index_obj; Type: TYPE; Schema: citydb_pkg; Owner: postgres
--

CREATE TYPE citydb_pkg.index_obj AS (
	index_name text,
	table_name text,
	attribute_name text,
	type numeric(1,0),
	srid integer,
	is_3d numeric(1,0)
);


ALTER TYPE citydb_pkg.index_obj OWNER TO postgres;

--
-- TOC entry 1454 (class 1255 OID 418609)
-- Name: box2envelope(public.box3d); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.box2envelope(box public.box3d) RETURNS public.geometry
    LANGUAGE plpgsql STABLE STRICT
    AS $$
DECLARE
  envelope GEOMETRY;
  db_srid INTEGER;
BEGIN
  -- get reference system of input geometry
  IF ST_SRID(box) = 0 THEN
    SELECT srid INTO db_srid FROM citydb.database_srs;
  ELSE
    db_srid := ST_SRID(box);
  END IF;

  SELECT ST_SetSRID(ST_MakePolygon(ST_MakeLine(
    ARRAY[
      ST_MakePoint(ST_XMin(box), ST_YMin(box), ST_ZMin(box)),
      ST_MakePoint(ST_XMax(box), ST_YMin(box), ST_ZMin(box)),
      ST_MakePoint(ST_XMax(box), ST_YMax(box), ST_ZMax(box)),
      ST_MakePoint(ST_XMin(box), ST_YMax(box), ST_ZMax(box)),
      ST_MakePoint(ST_XMin(box), ST_YMin(box), ST_ZMin(box))
    ]
  )), db_srid) INTO envelope;

  RETURN envelope;
END;
$$;


ALTER FUNCTION citydb.box2envelope(box public.box3d) OWNER TO postgres;

--
-- TOC entry 1500 (class 1255 OID 418656)
-- Name: cleanup_appearances(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.cleanup_appearances(only_global integer DEFAULT 1) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id int;
  app_id int;
BEGIN
  PERFORM citydb.del_surface_data(array_agg(s.id))
    FROM citydb.surface_data s 
    LEFT OUTER JOIN citydb.textureparam t ON s.id = t.surface_data_id
    WHERE t.surface_data_id IS NULL;

    IF only_global=1 THEN
      FOR app_id IN
        SELECT a.id FROM citydb.appearance a
          LEFT OUTER JOIN citydb.appear_to_surface_data asd ON a.id=asd.appearance_id
            WHERE a.cityobject_id IS NULL AND asd.appearance_id IS NULL
      LOOP
        DELETE FROM citydb.appearance WHERE id = app_id RETURNING id INTO deleted_id;
        RETURN NEXT deleted_id;
      END LOOP;
    ELSE
      FOR app_id IN
        SELECT a.id FROM citydb.appearance a
          LEFT OUTER JOIN citydb.appear_to_surface_data asd ON a.id=asd.appearance_id
            WHERE asd.appearance_id IS NULL
      LOOP
        DELETE FROM citydb.appearance WHERE id = app_id RETURNING id INTO deleted_id;
        RETURN NEXT deleted_id;
      END LOOP;
    END IF;

  RETURN;
END;
$$;


ALTER FUNCTION citydb.cleanup_appearances(only_global integer) OWNER TO postgres;

--
-- TOC entry 1501 (class 1255 OID 418657)
-- Name: cleanup_schema(); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.cleanup_schema() RETURNS SETOF void
    LANGUAGE plpgsql
    AS $$
-- Function for cleaning up data schema
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT table_name FROM information_schema.tables where table_schema = 'citydb'
    AND table_name <> 'database_srs'
    AND table_name <> 'objectclass'
    AND table_name <> 'index_table'
    AND table_name <> 'ade'
    AND table_name <> 'schema'
    AND table_name <> 'schema_to_objectclass'
    AND table_name <> 'schema_referencing'
    AND table_name <> 'aggregation_info'
    AND table_name NOT LIKE 'tmp_%'
  LOOP
    EXECUTE format('TRUNCATE TABLE citydb.%I CASCADE', rec.table_name);
  END LOOP;

  FOR rec IN 
    SELECT sequence_name FROM information_schema.sequences where sequence_schema = 'citydb'
    AND sequence_name <> 'ade_seq'
    AND sequence_name <> 'schema_seq'
  LOOP
    EXECUTE format('ALTER SEQUENCE citydb.%I RESTART', rec.sequence_name);	
  END LOOP;
END;
$$;


ALTER FUNCTION citydb.cleanup_schema() OWNER TO postgres;

--
-- TOC entry 1502 (class 1255 OID 418658)
-- Name: cleanup_table(text); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.cleanup_table(tab_name text) RETURNS SETOF integer
    LANGUAGE plpgsql
    AS $$
DECLARE
  rec RECORD;
  rec_id INTEGER;
  where_clause TEXT;
  query_ddl TEXT;
  counter INTEGER;
  table_alias TEXT;
  table_name_with_schemaprefix TEXT;
  del_func_name TEXT;
  schema_name TEXT;
  deleted_id INTEGER;
BEGIN
  schema_name = 'citydb';
  IF md5(schema_name) <> '373663016e8a76eedd0e1ac37f392d2a' THEN
    table_name_with_schemaprefix = schema_name || '.' || tab_name;
  ELSE
    table_name_with_schemaprefix = tab_name;
  END IF;

  counter = 0;
  del_func_name = 'del_' || tab_name;
  query_ddl = 'SELECT id FROM ' || schema_name || '.' || tab_name || ' WHERE id IN ('
    || 'SELECT a.id FROM ' || schema_name || '.' || tab_name || ' a';

  FOR rec IN
    SELECT
      c.confrelid::regclass::text AS root_table_name,
      c.conrelid::regclass::text AS fk_table_name,
      a.attname::text AS fk_column_name
    FROM
      pg_constraint c
    JOIN
      pg_attribute a
      ON a.attrelid = c.conrelid
      AND a.attnum = ANY (c.conkey)
    WHERE
      upper(c.confrelid::regclass::text) = upper(table_name_with_schemaprefix)
      AND c.conrelid <> c.confrelid
      AND c.contype = 'f'
    ORDER BY
      fk_table_name,
      fk_column_name
  LOOP
    counter = counter + 1;
    table_alias = 'n' || counter;
    IF counter = 1 THEN
      where_clause = ' WHERE ' || table_alias || '.' || rec.fk_column_name || ' IS NULL';
    ELSE
      where_clause = where_clause || ' AND ' || table_alias || '.' || rec.fk_column_name || ' IS NULL';
    END IF;

    IF md5(schema_name) <> '373663016e8a76eedd0e1ac37f392d2a' THEN
      query_ddl = query_ddl || ' LEFT JOIN ' || rec.fk_table_name || ' ' || table_alias || ' ON '
        || table_alias || '.' || rec.fk_column_name || ' = a.id';
    ELSE
      query_ddl = query_ddl || ' LEFT JOIN ' || schema_name || '.' || rec.fk_table_name || ' ' || table_alias || ' ON '
        || table_alias || '.' || rec.fk_column_name || ' = a.id';
    END IF;
  END LOOP;

  query_ddl = query_ddl || where_clause || ')';

  FOR rec_id IN EXECUTE query_ddl LOOP
    EXECUTE 'SELECT ' || schema_name || '.' || del_func_name || '(' || rec_id || ')' INTO deleted_id;
    RETURN NEXT deleted_id;
  END LOOP;

  RETURN;
END;
$$;


ALTER FUNCTION citydb.cleanup_table(tab_name text) OWNER TO postgres;

--
-- TOC entry 1504 (class 1255 OID 418660)
-- Name: del_address(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_address(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_address(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_address(pid integer) OWNER TO postgres;

--
-- TOC entry 1503 (class 1255 OID 418659)
-- Name: del_address(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_address(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
BEGIN
  -- delete citydb.addresss
  WITH delete_objects AS (
    DELETE FROM
      citydb.address t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_address(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1506 (class 1255 OID 418662)
-- Name: del_appearance(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_appearance(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_appearance(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_appearance(pid integer) OWNER TO postgres;

--
-- TOC entry 1505 (class 1255 OID 418661)
-- Name: del_appearance(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_appearance(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  surface_data_ids int[] := '{}';
BEGIN
  -- delete references to surface_datas
  WITH del_surface_data_refs AS (
    DELETE FROM
      citydb.appear_to_surface_data t
    USING
      unnest($1) a(a_id)
    WHERE
      t.appearance_id = a.a_id
    RETURNING
      t.surface_data_id
  )
  SELECT
    array_agg(surface_data_id)
  INTO
    surface_data_ids
  FROM
    del_surface_data_refs;

  -- delete citydb.surface_data(s)
  IF -1 = ALL(surface_data_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_data(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_data_ids) AS a_id) a
    LEFT JOIN
      citydb.appear_to_surface_data n1
      ON n1.surface_data_id  = a.a_id
    WHERE n1.surface_data_id IS NULL;
  END IF;

  -- delete citydb.appearances
  WITH delete_objects AS (
    DELETE FROM
      citydb.appearance t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_appearance(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1508 (class 1255 OID 418664)
-- Name: del_breakline_relief(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_breakline_relief(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_breakline_relief(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_breakline_relief(pid integer) OWNER TO postgres;

--
-- TOC entry 1507 (class 1255 OID 418663)
-- Name: del_breakline_relief(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_breakline_relief(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
BEGIN
  -- delete citydb.breakline_reliefs
  WITH delete_objects AS (
    DELETE FROM
      citydb.breakline_relief t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF $2 <> 1 THEN
    -- delete relief_component
    PERFORM citydb.del_relief_component(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_breakline_relief(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1510 (class 1255 OID 418666)
-- Name: del_bridge(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_bridge(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_bridge(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_bridge(pid integer) OWNER TO postgres;

--
-- TOC entry 1509 (class 1255 OID 418665)
-- Name: del_bridge(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_bridge(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  address_ids int[] := '{}';
  surface_geometry_ids int[] := '{}';
BEGIN
  -- delete referenced parts
  PERFORM
    citydb.del_bridge(array_agg(t.id))
  FROM
    citydb.bridge t,
    unnest($1) a(a_id)
  WHERE
    t.bridge_parent_id = a.a_id
    AND t.id <> a.a_id;

  -- delete referenced parts
  PERFORM
    citydb.del_bridge(array_agg(t.id))
  FROM
    citydb.bridge t,
    unnest($1) a(a_id)
  WHERE
    t.bridge_root_id = a.a_id
    AND t.id <> a.a_id;

  -- delete references to addresss
  WITH del_address_refs AS (
    DELETE FROM
      citydb.address_to_bridge t
    USING
      unnest($1) a(a_id)
    WHERE
      t.bridge_id = a.a_id
    RETURNING
      t.address_id
  )
  SELECT
    array_agg(address_id)
  INTO
    address_ids
  FROM
    del_address_refs;

  -- delete citydb.address(s)
  IF -1 = ALL(address_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_address(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(address_ids) AS a_id) a
    LEFT JOIN
      citydb.address_to_bridge n1
      ON n1.address_id  = a.a_id
    LEFT JOIN
      citydb.address_to_building n2
      ON n2.address_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n3
      ON n3.address_id  = a.a_id
    LEFT JOIN
      citydb.opening n4
      ON n4.address_id  = a.a_id
    WHERE n1.address_id IS NULL
      AND n2.address_id IS NULL
      AND n3.address_id IS NULL
      AND n4.address_id IS NULL;
  END IF;

  --delete bridge_constr_elements
  PERFORM
    citydb.del_bridge_constr_element(array_agg(t.id))
  FROM
    citydb.bridge_constr_element t,
    unnest($1) a(a_id)
  WHERE
    t.bridge_id = a.a_id;

  --delete bridge_installations
  PERFORM
    citydb.del_bridge_installation(array_agg(t.id))
  FROM
    citydb.bridge_installation t,
    unnest($1) a(a_id)
  WHERE
    t.bridge_id = a.a_id;

  --delete bridge_rooms
  PERFORM
    citydb.del_bridge_room(array_agg(t.id))
  FROM
    citydb.bridge_room t,
    unnest($1) a(a_id)
  WHERE
    t.bridge_id = a.a_id;

  --delete bridge_thematic_surfaces
  PERFORM
    citydb.del_bridge_thematic_surface(array_agg(t.id))
  FROM
    citydb.bridge_thematic_surface t,
    unnest($1) a(a_id)
  WHERE
    t.bridge_id = a.a_id;

  -- delete citydb.bridges
  WITH delete_objects AS (
    DELETE FROM
      citydb.bridge t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod1_multi_surface_id,
      lod2_multi_surface_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id,
      lod1_solid_id,
      lod2_solid_id,
      lod3_solid_id,
      lod4_solid_id
  )
  SELECT
    array_agg(id),
    array_agg(lod1_multi_surface_id) ||
    array_agg(lod2_multi_surface_id) ||
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id) ||
    array_agg(lod1_solid_id) ||
    array_agg(lod2_solid_id) ||
    array_agg(lod3_solid_id) ||
    array_agg(lod4_solid_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_bridge(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1512 (class 1255 OID 418668)
-- Name: del_bridge_constr_element(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_bridge_constr_element(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_bridge_constr_element(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_bridge_constr_element(pid integer) OWNER TO postgres;

--
-- TOC entry 1511 (class 1255 OID 418667)
-- Name: del_bridge_constr_element(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_bridge_constr_element(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids int[] := '{}';
  surface_geometry_ids int[] := '{}';
BEGIN
  -- delete citydb.bridge_constr_elements
  WITH delete_objects AS (
    DELETE FROM
      citydb.bridge_constr_element t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod1_implicit_rep_id,
      lod2_implicit_rep_id,
      lod3_implicit_rep_id,
      lod4_implicit_rep_id,
      lod1_brep_id,
      lod2_brep_id,
      lod3_brep_id,
      lod4_brep_id
  )
  SELECT
    array_agg(id),
    array_agg(lod1_implicit_rep_id) ||
    array_agg(lod2_implicit_rep_id) ||
    array_agg(lod3_implicit_rep_id) ||
    array_agg(lod4_implicit_rep_id),
    array_agg(lod1_brep_id) ||
    array_agg(lod2_brep_id) ||
    array_agg(lod3_brep_id) ||
    array_agg(lod4_brep_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_bridge_constr_element(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1514 (class 1255 OID 418670)
-- Name: del_bridge_furniture(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_bridge_furniture(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_bridge_furniture(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_bridge_furniture(pid integer) OWNER TO postgres;

--
-- TOC entry 1513 (class 1255 OID 418669)
-- Name: del_bridge_furniture(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_bridge_furniture(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids int[] := '{}';
  surface_geometry_ids int[] := '{}';
BEGIN
  -- delete citydb.bridge_furnitures
  WITH delete_objects AS (
    DELETE FROM
      citydb.bridge_furniture t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod4_implicit_rep_id,
      lod4_brep_id
  )
  SELECT
    array_agg(id),
    array_agg(lod4_implicit_rep_id),
    array_agg(lod4_brep_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_bridge_furniture(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1516 (class 1255 OID 418672)
-- Name: del_bridge_installation(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_bridge_installation(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_bridge_installation(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_bridge_installation(pid integer) OWNER TO postgres;

--
-- TOC entry 1515 (class 1255 OID 418671)
-- Name: del_bridge_installation(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_bridge_installation(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids int[] := '{}';
  surface_geometry_ids int[] := '{}';
BEGIN
  --delete bridge_thematic_surfaces
  PERFORM
    citydb.del_bridge_thematic_surface(array_agg(t.id))
  FROM
    citydb.bridge_thematic_surface t,
    unnest($1) a(a_id)
  WHERE
    t.bridge_installation_id = a.a_id;

  -- delete citydb.bridge_installations
  WITH delete_objects AS (
    DELETE FROM
      citydb.bridge_installation t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod2_implicit_rep_id,
      lod3_implicit_rep_id,
      lod4_implicit_rep_id,
      lod2_brep_id,
      lod3_brep_id,
      lod4_brep_id
  )
  SELECT
    array_agg(id),
    array_agg(lod2_implicit_rep_id) ||
    array_agg(lod3_implicit_rep_id) ||
    array_agg(lod4_implicit_rep_id),
    array_agg(lod2_brep_id) ||
    array_agg(lod3_brep_id) ||
    array_agg(lod4_brep_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_bridge_installation(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1518 (class 1255 OID 418674)
-- Name: del_bridge_opening(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_bridge_opening(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_bridge_opening(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_bridge_opening(pid integer) OWNER TO postgres;

--
-- TOC entry 1517 (class 1255 OID 418673)
-- Name: del_bridge_opening(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_bridge_opening(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids int[] := '{}';
  surface_geometry_ids int[] := '{}';
  address_ids int[] := '{}';
BEGIN
  -- delete citydb.bridge_openings
  WITH delete_objects AS (
    DELETE FROM
      citydb.bridge_opening t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod3_implicit_rep_id,
      lod4_implicit_rep_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id,
      address_id
  )
  SELECT
    array_agg(id),
    array_agg(lod3_implicit_rep_id) ||
    array_agg(lod4_implicit_rep_id),
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id),
    array_agg(address_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids,
    address_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  -- delete citydb.address(s)
  IF -1 = ALL(address_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_address(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(address_ids) AS a_id) a
    LEFT JOIN
      citydb.address_to_bridge n1
      ON n1.address_id  = a.a_id
    LEFT JOIN
      citydb.address_to_building n2
      ON n2.address_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n3
      ON n3.address_id  = a.a_id
    LEFT JOIN
      citydb.opening n4
      ON n4.address_id  = a.a_id
    WHERE n1.address_id IS NULL
      AND n2.address_id IS NULL
      AND n3.address_id IS NULL
      AND n4.address_id IS NULL;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_bridge_opening(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1520 (class 1255 OID 418676)
-- Name: del_bridge_room(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_bridge_room(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_bridge_room(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_bridge_room(pid integer) OWNER TO postgres;

--
-- TOC entry 1519 (class 1255 OID 418675)
-- Name: del_bridge_room(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_bridge_room(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids int[] := '{}';
BEGIN
  --delete bridge_furnitures
  PERFORM
    citydb.del_bridge_furniture(array_agg(t.id))
  FROM
    citydb.bridge_furniture t,
    unnest($1) a(a_id)
  WHERE
    t.bridge_room_id = a.a_id;

  --delete bridge_installations
  PERFORM
    citydb.del_bridge_installation(array_agg(t.id))
  FROM
    citydb.bridge_installation t,
    unnest($1) a(a_id)
  WHERE
    t.bridge_room_id = a.a_id;

  --delete bridge_thematic_surfaces
  PERFORM
    citydb.del_bridge_thematic_surface(array_agg(t.id))
  FROM
    citydb.bridge_thematic_surface t,
    unnest($1) a(a_id)
  WHERE
    t.bridge_room_id = a.a_id;

  -- delete citydb.bridge_rooms
  WITH delete_objects AS (
    DELETE FROM
      citydb.bridge_room t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod4_multi_surface_id,
      lod4_solid_id
  )
  SELECT
    array_agg(id),
    array_agg(lod4_multi_surface_id) ||
    array_agg(lod4_solid_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_bridge_room(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1522 (class 1255 OID 418678)
-- Name: del_bridge_thematic_surface(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_bridge_thematic_surface(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_bridge_thematic_surface(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_bridge_thematic_surface(pid integer) OWNER TO postgres;

--
-- TOC entry 1521 (class 1255 OID 418677)
-- Name: del_bridge_thematic_surface(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_bridge_thematic_surface(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  bridge_opening_ids int[] := '{}';
  surface_geometry_ids int[] := '{}';
BEGIN
  -- delete references to bridge_openings
  WITH del_bridge_opening_refs AS (
    DELETE FROM
      citydb.bridge_open_to_them_srf t
    USING
      unnest($1) a(a_id)
    WHERE
      t.bridge_thematic_surface_id = a.a_id
    RETURNING
      t.bridge_opening_id
  )
  SELECT
    array_agg(bridge_opening_id)
  INTO
    bridge_opening_ids
  FROM
    del_bridge_opening_refs;

  -- delete citydb.bridge_opening(s)
  IF -1 = ALL(bridge_opening_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_bridge_opening(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(bridge_opening_ids) AS a_id) a;
  END IF;

  -- delete citydb.bridge_thematic_surfaces
  WITH delete_objects AS (
    DELETE FROM
      citydb.bridge_thematic_surface t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod2_multi_surface_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id
  )
  SELECT
    array_agg(id),
    array_agg(lod2_multi_surface_id) ||
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_bridge_thematic_surface(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1524 (class 1255 OID 418680)
-- Name: del_building(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_building(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_building(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_building(pid integer) OWNER TO postgres;

--
-- TOC entry 1523 (class 1255 OID 418679)
-- Name: del_building(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_building(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  address_ids int[] := '{}';
  surface_geometry_ids int[] := '{}';
BEGIN
  -- delete referenced parts
  PERFORM
    citydb.del_building(array_agg(t.id))
  FROM
    citydb.building t,
    unnest($1) a(a_id)
  WHERE
    t.building_parent_id = a.a_id
    AND t.id <> a.a_id;

  -- delete referenced parts
  PERFORM
    citydb.del_building(array_agg(t.id))
  FROM
    citydb.building t,
    unnest($1) a(a_id)
  WHERE
    t.building_root_id = a.a_id
    AND t.id <> a.a_id;

  -- delete references to addresss
  WITH del_address_refs AS (
    DELETE FROM
      citydb.address_to_building t
    USING
      unnest($1) a(a_id)
    WHERE
      t.building_id = a.a_id
    RETURNING
      t.address_id
  )
  SELECT
    array_agg(address_id)
  INTO
    address_ids
  FROM
    del_address_refs;

  -- delete citydb.address(s)
  IF -1 = ALL(address_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_address(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(address_ids) AS a_id) a
    LEFT JOIN
      citydb.address_to_bridge n1
      ON n1.address_id  = a.a_id
    LEFT JOIN
      citydb.address_to_building n2
      ON n2.address_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n3
      ON n3.address_id  = a.a_id
    LEFT JOIN
      citydb.opening n4
      ON n4.address_id  = a.a_id
    WHERE n1.address_id IS NULL
      AND n2.address_id IS NULL
      AND n3.address_id IS NULL
      AND n4.address_id IS NULL;
  END IF;

  --delete building_installations
  PERFORM
    citydb.del_building_installation(array_agg(t.id))
  FROM
    citydb.building_installation t,
    unnest($1) a(a_id)
  WHERE
    t.building_id = a.a_id;

  --delete rooms
  PERFORM
    citydb.del_room(array_agg(t.id))
  FROM
    citydb.room t,
    unnest($1) a(a_id)
  WHERE
    t.building_id = a.a_id;

  --delete thematic_surfaces
  PERFORM
    citydb.del_thematic_surface(array_agg(t.id))
  FROM
    citydb.thematic_surface t,
    unnest($1) a(a_id)
  WHERE
    t.building_id = a.a_id;

  -- delete citydb.buildings
  WITH delete_objects AS (
    DELETE FROM
      citydb.building t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod0_footprint_id,
      lod0_roofprint_id,
      lod1_multi_surface_id,
      lod2_multi_surface_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id,
      lod1_solid_id,
      lod2_solid_id,
      lod3_solid_id,
      lod4_solid_id
  )
  SELECT
    array_agg(id),
    array_agg(lod0_footprint_id) ||
    array_agg(lod0_roofprint_id) ||
    array_agg(lod1_multi_surface_id) ||
    array_agg(lod2_multi_surface_id) ||
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id) ||
    array_agg(lod1_solid_id) ||
    array_agg(lod2_solid_id) ||
    array_agg(lod3_solid_id) ||
    array_agg(lod4_solid_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_building(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1526 (class 1255 OID 418682)
-- Name: del_building_furniture(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_building_furniture(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_building_furniture(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_building_furniture(pid integer) OWNER TO postgres;

--
-- TOC entry 1525 (class 1255 OID 418681)
-- Name: del_building_furniture(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_building_furniture(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids int[] := '{}';
  surface_geometry_ids int[] := '{}';
BEGIN
  -- delete citydb.building_furnitures
  WITH delete_objects AS (
    DELETE FROM
      citydb.building_furniture t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod4_implicit_rep_id,
      lod4_brep_id
  )
  SELECT
    array_agg(id),
    array_agg(lod4_implicit_rep_id),
    array_agg(lod4_brep_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_building_furniture(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1528 (class 1255 OID 418684)
-- Name: del_building_installation(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_building_installation(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_building_installation(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_building_installation(pid integer) OWNER TO postgres;

--
-- TOC entry 1527 (class 1255 OID 418683)
-- Name: del_building_installation(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_building_installation(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids int[] := '{}';
  surface_geometry_ids int[] := '{}';
BEGIN
  --delete thematic_surfaces
  PERFORM
    citydb.del_thematic_surface(array_agg(t.id))
  FROM
    citydb.thematic_surface t,
    unnest($1) a(a_id)
  WHERE
    t.building_installation_id = a.a_id;

  -- delete citydb.building_installations
  WITH delete_objects AS (
    DELETE FROM
      citydb.building_installation t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod2_implicit_rep_id,
      lod3_implicit_rep_id,
      lod4_implicit_rep_id,
      lod2_brep_id,
      lod3_brep_id,
      lod4_brep_id
  )
  SELECT
    array_agg(id),
    array_agg(lod2_implicit_rep_id) ||
    array_agg(lod3_implicit_rep_id) ||
    array_agg(lod4_implicit_rep_id),
    array_agg(lod2_brep_id) ||
    array_agg(lod3_brep_id) ||
    array_agg(lod4_brep_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_building_installation(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1530 (class 1255 OID 418686)
-- Name: del_city_furniture(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_city_furniture(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_city_furniture(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_city_furniture(pid integer) OWNER TO postgres;

--
-- TOC entry 1529 (class 1255 OID 418685)
-- Name: del_city_furniture(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_city_furniture(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids int[] := '{}';
  surface_geometry_ids int[] := '{}';
BEGIN
  -- delete citydb.city_furnitures
  WITH delete_objects AS (
    DELETE FROM
      citydb.city_furniture t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod1_implicit_rep_id,
      lod2_implicit_rep_id,
      lod3_implicit_rep_id,
      lod4_implicit_rep_id,
      lod1_brep_id,
      lod2_brep_id,
      lod3_brep_id,
      lod4_brep_id
  )
  SELECT
    array_agg(id),
    array_agg(lod1_implicit_rep_id) ||
    array_agg(lod2_implicit_rep_id) ||
    array_agg(lod3_implicit_rep_id) ||
    array_agg(lod4_implicit_rep_id),
    array_agg(lod1_brep_id) ||
    array_agg(lod2_brep_id) ||
    array_agg(lod3_brep_id) ||
    array_agg(lod4_brep_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_city_furniture(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1532 (class 1255 OID 418688)
-- Name: del_citymodel(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_citymodel(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_citymodel(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_citymodel(pid integer) OWNER TO postgres;

--
-- TOC entry 1531 (class 1255 OID 418687)
-- Name: del_citymodel(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_citymodel(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  cityobject_ids int[] := '{}';
BEGIN
  --delete appearances
  PERFORM
    citydb.del_appearance(array_agg(t.id))
  FROM
    citydb.appearance t,
    unnest($1) a(a_id)
  WHERE
    t.citymodel_id = a.a_id;

  -- delete references to cityobjects
  WITH del_cityobject_refs AS (
    DELETE FROM
      citydb.cityobject_member t
    USING
      unnest($1) a(a_id)
    WHERE
      t.citymodel_id = a.a_id
    RETURNING
      t.cityobject_id
  )
  SELECT
    array_agg(cityobject_id)
  INTO
    cityobject_ids
  FROM
    del_cityobject_refs;

  -- delete citydb.cityobject(s)
  IF -1 = ALL(cityobject_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_cityobject(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(cityobject_ids) AS a_id) a
    LEFT JOIN
      citydb.cityobject_member n1
      ON n1.cityobject_id  = a.a_id
    LEFT JOIN
      citydb.group_to_cityobject n2
      ON n2.cityobject_id  = a.a_id
    WHERE n1.cityobject_id IS NULL
      AND n2.cityobject_id IS NULL;
  END IF;

  -- delete citydb.citymodels
  WITH delete_objects AS (
    DELETE FROM
      citydb.citymodel t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_citymodel(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1534 (class 1255 OID 418691)
-- Name: del_cityobject(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_cityobject(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_cityobject(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_cityobject(pid integer) OWNER TO postgres;

--
-- TOC entry 1533 (class 1255 OID 418689)
-- Name: del_cityobject(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_cityobject(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
BEGIN
  --delete appearances
  PERFORM
    citydb.del_appearance(array_agg(t.id))
  FROM
    citydb.appearance t,
    unnest($1) a(a_id)
  WHERE
    t.cityobject_id = a.a_id;

  --delete cityobject_genericattribs
  PERFORM
    citydb.del_cityobject_genericattrib(array_agg(t.id))
  FROM
    citydb.cityobject_genericattrib t,
    unnest($1) a(a_id)
  WHERE
    t.cityobject_id = a.a_id;

  --delete external_references
  PERFORM
    citydb.del_external_reference(array_agg(t.id))
  FROM
    citydb.external_reference t,
    unnest($1) a(a_id)
  WHERE
    t.cityobject_id = a.a_id;

  IF $2 <> 2 THEN
    FOR rec IN
      SELECT
        co.id, co.objectclass_id
      FROM
        citydb.cityobject co, unnest($1) a(a_id)
      WHERE
        co.id = a.a_id
    LOOP
      object_id := rec.id::integer;
      objectclass_id := rec.objectclass_id::integer;
      CASE
        -- delete land_use
        WHEN objectclass_id = 4 THEN
          dummy_id := citydb.del_land_use(array_agg(object_id), 1);
        -- delete generic_cityobject
        WHEN objectclass_id = 5 THEN
          dummy_id := citydb.del_generic_cityobject(array_agg(object_id), 1);
        -- delete solitary_vegetat_object
        WHEN objectclass_id = 7 THEN
          dummy_id := citydb.del_solitary_vegetat_object(array_agg(object_id), 1);
        -- delete plant_cover
        WHEN objectclass_id = 8 THEN
          dummy_id := citydb.del_plant_cover(array_agg(object_id), 1);
        -- delete waterbody
        WHEN objectclass_id = 9 THEN
          dummy_id := citydb.del_waterbody(array_agg(object_id), 1);
        -- delete waterboundary_surface
        WHEN objectclass_id = 10 THEN
          dummy_id := citydb.del_waterboundary_surface(array_agg(object_id), 1);
        -- delete waterboundary_surface
        WHEN objectclass_id = 11 THEN
          dummy_id := citydb.del_waterboundary_surface(array_agg(object_id), 1);
        -- delete waterboundary_surface
        WHEN objectclass_id = 12 THEN
          dummy_id := citydb.del_waterboundary_surface(array_agg(object_id), 1);
        -- delete waterboundary_surface
        WHEN objectclass_id = 13 THEN
          dummy_id := citydb.del_waterboundary_surface(array_agg(object_id), 1);
        -- delete relief_feature
        WHEN objectclass_id = 14 THEN
          dummy_id := citydb.del_relief_feature(array_agg(object_id), 1);
        -- delete relief_component
        WHEN objectclass_id = 15 THEN
          dummy_id := citydb.del_relief_component(array_agg(object_id), 1);
        -- delete tin_relief
        WHEN objectclass_id = 16 THEN
          dummy_id := citydb.del_tin_relief(array_agg(object_id), 0);
        -- delete masspoint_relief
        WHEN objectclass_id = 17 THEN
          dummy_id := citydb.del_masspoint_relief(array_agg(object_id), 0);
        -- delete breakline_relief
        WHEN objectclass_id = 18 THEN
          dummy_id := citydb.del_breakline_relief(array_agg(object_id), 0);
        -- delete raster_relief
        WHEN objectclass_id = 19 THEN
          dummy_id := citydb.del_raster_relief(array_agg(object_id), 0);
        -- delete city_furniture
        WHEN objectclass_id = 21 THEN
          dummy_id := citydb.del_city_furniture(array_agg(object_id), 1);
        -- delete cityobjectgroup
        WHEN objectclass_id = 23 THEN
          dummy_id := citydb.del_cityobjectgroup(array_agg(object_id), 1);
        -- delete building
        WHEN objectclass_id = 24 THEN
          dummy_id := citydb.del_building(array_agg(object_id), 1);
        -- delete building
        WHEN objectclass_id = 25 THEN
          dummy_id := citydb.del_building(array_agg(object_id), 1);
        -- delete building
        WHEN objectclass_id = 26 THEN
          dummy_id := citydb.del_building(array_agg(object_id), 1);
        -- delete building_installation
        WHEN objectclass_id = 27 THEN
          dummy_id := citydb.del_building_installation(array_agg(object_id), 1);
        -- delete building_installation
        WHEN objectclass_id = 28 THEN
          dummy_id := citydb.del_building_installation(array_agg(object_id), 1);
        -- delete thematic_surface
        WHEN objectclass_id = 29 THEN
          dummy_id := citydb.del_thematic_surface(array_agg(object_id), 1);
        -- delete thematic_surface
        WHEN objectclass_id = 30 THEN
          dummy_id := citydb.del_thematic_surface(array_agg(object_id), 1);
        -- delete thematic_surface
        WHEN objectclass_id = 31 THEN
          dummy_id := citydb.del_thematic_surface(array_agg(object_id), 1);
        -- delete thematic_surface
        WHEN objectclass_id = 32 THEN
          dummy_id := citydb.del_thematic_surface(array_agg(object_id), 1);
        -- delete thematic_surface
        WHEN objectclass_id = 33 THEN
          dummy_id := citydb.del_thematic_surface(array_agg(object_id), 1);
        -- delete thematic_surface
        WHEN objectclass_id = 34 THEN
          dummy_id := citydb.del_thematic_surface(array_agg(object_id), 1);
        -- delete thematic_surface
        WHEN objectclass_id = 35 THEN
          dummy_id := citydb.del_thematic_surface(array_agg(object_id), 1);
        -- delete thematic_surface
        WHEN objectclass_id = 36 THEN
          dummy_id := citydb.del_thematic_surface(array_agg(object_id), 1);
        -- delete opening
        WHEN objectclass_id = 37 THEN
          dummy_id := citydb.del_opening(array_agg(object_id), 1);
        -- delete opening
        WHEN objectclass_id = 38 THEN
          dummy_id := citydb.del_opening(array_agg(object_id), 1);
        -- delete opening
        WHEN objectclass_id = 39 THEN
          dummy_id := citydb.del_opening(array_agg(object_id), 1);
        -- delete building_furniture
        WHEN objectclass_id = 40 THEN
          dummy_id := citydb.del_building_furniture(array_agg(object_id), 1);
        -- delete room
        WHEN objectclass_id = 41 THEN
          dummy_id := citydb.del_room(array_agg(object_id), 1);
        -- delete transportation_complex
        WHEN objectclass_id = 42 THEN
          dummy_id := citydb.del_transportation_complex(array_agg(object_id), 1);
        -- delete transportation_complex
        WHEN objectclass_id = 43 THEN
          dummy_id := citydb.del_transportation_complex(array_agg(object_id), 1);
        -- delete transportation_complex
        WHEN objectclass_id = 44 THEN
          dummy_id := citydb.del_transportation_complex(array_agg(object_id), 1);
        -- delete transportation_complex
        WHEN objectclass_id = 45 THEN
          dummy_id := citydb.del_transportation_complex(array_agg(object_id), 1);
        -- delete transportation_complex
        WHEN objectclass_id = 46 THEN
          dummy_id := citydb.del_transportation_complex(array_agg(object_id), 1);
        -- delete traffic_area
        WHEN objectclass_id = 47 THEN
          dummy_id := citydb.del_traffic_area(array_agg(object_id), 1);
        -- delete traffic_area
        WHEN objectclass_id = 48 THEN
          dummy_id := citydb.del_traffic_area(array_agg(object_id), 1);
        -- delete appearance
        WHEN objectclass_id = 50 THEN
          dummy_id := citydb.del_appearance(array_agg(object_id), 0);
        -- delete surface_data
        WHEN objectclass_id = 51 THEN
          dummy_id := citydb.del_surface_data(array_agg(object_id), 0);
        -- delete surface_data
        WHEN objectclass_id = 52 THEN
          dummy_id := citydb.del_surface_data(array_agg(object_id), 0);
        -- delete surface_data
        WHEN objectclass_id = 53 THEN
          dummy_id := citydb.del_surface_data(array_agg(object_id), 0);
        -- delete surface_data
        WHEN objectclass_id = 54 THEN
          dummy_id := citydb.del_surface_data(array_agg(object_id), 0);
        -- delete surface_data
        WHEN objectclass_id = 55 THEN
          dummy_id := citydb.del_surface_data(array_agg(object_id), 0);
        -- delete citymodel
        WHEN objectclass_id = 57 THEN
          dummy_id := citydb.del_citymodel(array_agg(object_id), 0);
        -- delete address
        WHEN objectclass_id = 58 THEN
          dummy_id := citydb.del_address(array_agg(object_id), 0);
        -- delete implicit_geometry
        WHEN objectclass_id = 59 THEN
          dummy_id := citydb.del_implicit_geometry(array_agg(object_id), 0);
        -- delete thematic_surface
        WHEN objectclass_id = 60 THEN
          dummy_id := citydb.del_thematic_surface(array_agg(object_id), 1);
        -- delete thematic_surface
        WHEN objectclass_id = 61 THEN
          dummy_id := citydb.del_thematic_surface(array_agg(object_id), 1);
        -- delete bridge
        WHEN objectclass_id = 62 THEN
          dummy_id := citydb.del_bridge(array_agg(object_id), 1);
        -- delete bridge
        WHEN objectclass_id = 63 THEN
          dummy_id := citydb.del_bridge(array_agg(object_id), 1);
        -- delete bridge
        WHEN objectclass_id = 64 THEN
          dummy_id := citydb.del_bridge(array_agg(object_id), 1);
        -- delete bridge_installation
        WHEN objectclass_id = 65 THEN
          dummy_id := citydb.del_bridge_installation(array_agg(object_id), 1);
        -- delete bridge_installation
        WHEN objectclass_id = 66 THEN
          dummy_id := citydb.del_bridge_installation(array_agg(object_id), 1);
        -- delete bridge_thematic_surface
        WHEN objectclass_id = 67 THEN
          dummy_id := citydb.del_bridge_thematic_surface(array_agg(object_id), 1);
        -- delete bridge_thematic_surface
        WHEN objectclass_id = 68 THEN
          dummy_id := citydb.del_bridge_thematic_surface(array_agg(object_id), 1);
        -- delete bridge_thematic_surface
        WHEN objectclass_id = 69 THEN
          dummy_id := citydb.del_bridge_thematic_surface(array_agg(object_id), 1);
        -- delete bridge_thematic_surface
        WHEN objectclass_id = 70 THEN
          dummy_id := citydb.del_bridge_thematic_surface(array_agg(object_id), 1);
        -- delete bridge_thematic_surface
        WHEN objectclass_id = 71 THEN
          dummy_id := citydb.del_bridge_thematic_surface(array_agg(object_id), 1);
        -- delete bridge_thematic_surface
        WHEN objectclass_id = 72 THEN
          dummy_id := citydb.del_bridge_thematic_surface(array_agg(object_id), 1);
        -- delete bridge_thematic_surface
        WHEN objectclass_id = 73 THEN
          dummy_id := citydb.del_bridge_thematic_surface(array_agg(object_id), 1);
        -- delete bridge_thematic_surface
        WHEN objectclass_id = 74 THEN
          dummy_id := citydb.del_bridge_thematic_surface(array_agg(object_id), 1);
        -- delete bridge_thematic_surface
        WHEN objectclass_id = 75 THEN
          dummy_id := citydb.del_bridge_thematic_surface(array_agg(object_id), 1);
        -- delete bridge_thematic_surface
        WHEN objectclass_id = 76 THEN
          dummy_id := citydb.del_bridge_thematic_surface(array_agg(object_id), 1);
        -- delete bridge_opening
        WHEN objectclass_id = 77 THEN
          dummy_id := citydb.del_bridge_opening(array_agg(object_id), 1);
        -- delete bridge_opening
        WHEN objectclass_id = 78 THEN
          dummy_id := citydb.del_bridge_opening(array_agg(object_id), 1);
        -- delete bridge_opening
        WHEN objectclass_id = 79 THEN
          dummy_id := citydb.del_bridge_opening(array_agg(object_id), 1);
        -- delete bridge_furniture
        WHEN objectclass_id = 80 THEN
          dummy_id := citydb.del_bridge_furniture(array_agg(object_id), 1);
        -- delete bridge_room
        WHEN objectclass_id = 81 THEN
          dummy_id := citydb.del_bridge_room(array_agg(object_id), 1);
        -- delete bridge_constr_element
        WHEN objectclass_id = 82 THEN
          dummy_id := citydb.del_bridge_constr_element(array_agg(object_id), 1);
        -- delete tunnel
        WHEN objectclass_id = 83 THEN
          dummy_id := citydb.del_tunnel(array_agg(object_id), 1);
        -- delete tunnel
        WHEN objectclass_id = 84 THEN
          dummy_id := citydb.del_tunnel(array_agg(object_id), 1);
        -- delete tunnel
        WHEN objectclass_id = 85 THEN
          dummy_id := citydb.del_tunnel(array_agg(object_id), 1);
        -- delete tunnel_installation
        WHEN objectclass_id = 86 THEN
          dummy_id := citydb.del_tunnel_installation(array_agg(object_id), 1);
        -- delete tunnel_installation
        WHEN objectclass_id = 87 THEN
          dummy_id := citydb.del_tunnel_installation(array_agg(object_id), 1);
        -- delete tunnel_thematic_surface
        WHEN objectclass_id = 88 THEN
          dummy_id := citydb.del_tunnel_thematic_surface(array_agg(object_id), 1);
        -- delete tunnel_thematic_surface
        WHEN objectclass_id = 89 THEN
          dummy_id := citydb.del_tunnel_thematic_surface(array_agg(object_id), 1);
        -- delete tunnel_thematic_surface
        WHEN objectclass_id = 90 THEN
          dummy_id := citydb.del_tunnel_thematic_surface(array_agg(object_id), 1);
        -- delete tunnel_thematic_surface
        WHEN objectclass_id = 91 THEN
          dummy_id := citydb.del_tunnel_thematic_surface(array_agg(object_id), 1);
        -- delete tunnel_thematic_surface
        WHEN objectclass_id = 92 THEN
          dummy_id := citydb.del_tunnel_thematic_surface(array_agg(object_id), 1);
        -- delete tunnel_thematic_surface
        WHEN objectclass_id = 93 THEN
          dummy_id := citydb.del_tunnel_thematic_surface(array_agg(object_id), 1);
        -- delete tunnel_thematic_surface
        WHEN objectclass_id = 94 THEN
          dummy_id := citydb.del_tunnel_thematic_surface(array_agg(object_id), 1);
        -- delete tunnel_thematic_surface
        WHEN objectclass_id = 95 THEN
          dummy_id := citydb.del_tunnel_thematic_surface(array_agg(object_id), 1);
        -- delete tunnel_thematic_surface
        WHEN objectclass_id = 96 THEN
          dummy_id := citydb.del_tunnel_thematic_surface(array_agg(object_id), 1);
        -- delete tunnel_thematic_surface
        WHEN objectclass_id = 97 THEN
          dummy_id := citydb.del_tunnel_thematic_surface(array_agg(object_id), 1);
        -- delete tunnel_opening
        WHEN objectclass_id = 98 THEN
          dummy_id := citydb.del_tunnel_opening(array_agg(object_id), 1);
        -- delete tunnel_opening
        WHEN objectclass_id = 99 THEN
          dummy_id := citydb.del_tunnel_opening(array_agg(object_id), 1);
        -- delete tunnel_opening
        WHEN objectclass_id = 100 THEN
          dummy_id := citydb.del_tunnel_opening(array_agg(object_id), 1);
        -- delete tunnel_furniture
        WHEN objectclass_id = 101 THEN
          dummy_id := citydb.del_tunnel_furniture(array_agg(object_id), 1);
        -- delete tunnel_hollow_space
        WHEN objectclass_id = 102 THEN
          dummy_id := citydb.del_tunnel_hollow_space(array_agg(object_id), 1);
        ELSE
          dummy_id := NULL;
      END CASE;

      IF dummy_id = object_id THEN
        deleted_child_ids := array_append(deleted_child_ids, dummy_id);
      END IF;
    END LOOP;
  END IF;

  -- delete citydb.cityobjects
  WITH delete_objects AS (
    DELETE FROM
      citydb.cityobject t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_cityobject(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1536 (class 1255 OID 418693)
-- Name: del_cityobject_genericattrib(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_cityobject_genericattrib(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_cityobject_genericattrib(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_cityobject_genericattrib(pid integer) OWNER TO postgres;

--
-- TOC entry 1535 (class 1255 OID 418692)
-- Name: del_cityobject_genericattrib(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_cityobject_genericattrib(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids int[] := '{}';
BEGIN
  -- delete referenced parts
  PERFORM
    citydb.del_cityobject_genericattrib(array_agg(t.id))
  FROM
    citydb.cityobject_genericattrib t,
    unnest($1) a(a_id)
  WHERE
    t.parent_genattrib_id = a.a_id
    AND t.id <> a.a_id;

  -- delete referenced parts
  PERFORM
    citydb.del_cityobject_genericattrib(array_agg(t.id))
  FROM
    citydb.cityobject_genericattrib t,
    unnest($1) a(a_id)
  WHERE
    t.root_genattrib_id = a.a_id
    AND t.id <> a.a_id;

  -- delete citydb.cityobject_genericattribs
  WITH delete_objects AS (
    DELETE FROM
      citydb.cityobject_genericattrib t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      surface_geometry_id
  )
  SELECT
    array_agg(id),
    array_agg(surface_geometry_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_cityobject_genericattrib(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1538 (class 1255 OID 418695)
-- Name: del_cityobjectgroup(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_cityobjectgroup(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_cityobjectgroup(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_cityobjectgroup(pid integer) OWNER TO postgres;

--
-- TOC entry 1537 (class 1255 OID 418694)
-- Name: del_cityobjectgroup(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_cityobjectgroup(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  cityobject_ids int[] := '{}';
  surface_geometry_ids int[] := '{}';
BEGIN
  -- delete references to cityobjects
  WITH del_cityobject_refs AS (
    DELETE FROM
      citydb.group_to_cityobject t
    USING
      unnest($1) a(a_id)
    WHERE
      t.cityobjectgroup_id = a.a_id
    RETURNING
      t.cityobject_id
  )
  SELECT
    array_agg(cityobject_id)
  INTO
    cityobject_ids
  FROM
    del_cityobject_refs;

  -- delete citydb.cityobject(s)
  IF -1 = ALL(cityobject_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_cityobject(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(cityobject_ids) AS a_id) a
    LEFT JOIN
      citydb.cityobject_member n1
      ON n1.cityobject_id  = a.a_id
    LEFT JOIN
      citydb.group_to_cityobject n2
      ON n2.cityobject_id  = a.a_id
    WHERE n1.cityobject_id IS NULL
      AND n2.cityobject_id IS NULL;
  END IF;

  -- delete citydb.cityobjectgroups
  WITH delete_objects AS (
    DELETE FROM
      citydb.cityobjectgroup t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      brep_id
  )
  SELECT
    array_agg(id),
    array_agg(brep_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_cityobjectgroup(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1539 (class 1255 OID 418696)
-- Name: del_cityobjects_by_lineage(text, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_cityobjects_by_lineage(lineage_value text, objectclass_id integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
-- Function for deleting cityobjects by lineage value
DECLARE
  deleted_ids int[] := '{}';
BEGIN
  IF $2 = 0 THEN
    SELECT array_agg(c.id) FROM
      citydb.cityobject c
    INTO
      deleted_ids
    WHERE
      c.lineage = $1;
  ELSE
    SELECT array_agg(c.id) FROM
      citydb.cityobject c
    INTO
      deleted_ids
    WHERE
      c.lineage = $1 AND c.objectclass_id = $2;
  END IF;

  IF -1 = ALL(deleted_ids) IS NOT NULL THEN
    PERFORM citydb.del_cityobject(deleted_ids);
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_cityobjects_by_lineage(lineage_value text, objectclass_id integer) OWNER TO postgres;

--
-- TOC entry 1541 (class 1255 OID 418698)
-- Name: del_external_reference(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_external_reference(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_external_reference(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_external_reference(pid integer) OWNER TO postgres;

--
-- TOC entry 1540 (class 1255 OID 418697)
-- Name: del_external_reference(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_external_reference(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
BEGIN
  -- delete citydb.external_references
  WITH delete_objects AS (
    DELETE FROM
      citydb.external_reference t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_external_reference(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1543 (class 1255 OID 418700)
-- Name: del_generic_cityobject(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_generic_cityobject(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_generic_cityobject(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_generic_cityobject(pid integer) OWNER TO postgres;

--
-- TOC entry 1542 (class 1255 OID 418699)
-- Name: del_generic_cityobject(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_generic_cityobject(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids int[] := '{}';
  surface_geometry_ids int[] := '{}';
BEGIN
  -- delete citydb.generic_cityobjects
  WITH delete_objects AS (
    DELETE FROM
      citydb.generic_cityobject t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod0_implicit_rep_id,
      lod1_implicit_rep_id,
      lod2_implicit_rep_id,
      lod3_implicit_rep_id,
      lod4_implicit_rep_id,
      lod0_brep_id,
      lod1_brep_id,
      lod2_brep_id,
      lod3_brep_id,
      lod4_brep_id
  )
  SELECT
    array_agg(id),
    array_agg(lod0_implicit_rep_id) ||
    array_agg(lod1_implicit_rep_id) ||
    array_agg(lod2_implicit_rep_id) ||
    array_agg(lod3_implicit_rep_id) ||
    array_agg(lod4_implicit_rep_id),
    array_agg(lod0_brep_id) ||
    array_agg(lod1_brep_id) ||
    array_agg(lod2_brep_id) ||
    array_agg(lod3_brep_id) ||
    array_agg(lod4_brep_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_generic_cityobject(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1545 (class 1255 OID 418702)
-- Name: del_grid_coverage(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_grid_coverage(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_grid_coverage(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_grid_coverage(pid integer) OWNER TO postgres;

--
-- TOC entry 1544 (class 1255 OID 418701)
-- Name: del_grid_coverage(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_grid_coverage(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
BEGIN
  -- delete citydb.grid_coverages
  WITH delete_objects AS (
    DELETE FROM
      citydb.grid_coverage t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_grid_coverage(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1547 (class 1255 OID 418704)
-- Name: del_implicit_geometry(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_implicit_geometry(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_implicit_geometry(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_implicit_geometry(pid integer) OWNER TO postgres;

--
-- TOC entry 1546 (class 1255 OID 418703)
-- Name: del_implicit_geometry(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_implicit_geometry(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids int[] := '{}';
BEGIN
  -- delete citydb.implicit_geometrys
  WITH delete_objects AS (
    DELETE FROM
      citydb.implicit_geometry t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      relative_brep_id
  )
  SELECT
    array_agg(id),
    array_agg(relative_brep_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_implicit_geometry(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1549 (class 1255 OID 418706)
-- Name: del_land_use(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_land_use(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_land_use(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_land_use(pid integer) OWNER TO postgres;

--
-- TOC entry 1548 (class 1255 OID 418705)
-- Name: del_land_use(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_land_use(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids int[] := '{}';
BEGIN
  -- delete citydb.land_uses
  WITH delete_objects AS (
    DELETE FROM
      citydb.land_use t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod0_multi_surface_id,
      lod1_multi_surface_id,
      lod2_multi_surface_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id
  )
  SELECT
    array_agg(id),
    array_agg(lod0_multi_surface_id) ||
    array_agg(lod1_multi_surface_id) ||
    array_agg(lod2_multi_surface_id) ||
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_land_use(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1551 (class 1255 OID 418708)
-- Name: del_masspoint_relief(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_masspoint_relief(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_masspoint_relief(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_masspoint_relief(pid integer) OWNER TO postgres;

--
-- TOC entry 1550 (class 1255 OID 418707)
-- Name: del_masspoint_relief(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_masspoint_relief(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
BEGIN
  -- delete citydb.masspoint_reliefs
  WITH delete_objects AS (
    DELETE FROM
      citydb.masspoint_relief t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF $2 <> 1 THEN
    -- delete relief_component
    PERFORM citydb.del_relief_component(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_masspoint_relief(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1553 (class 1255 OID 418710)
-- Name: del_opening(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_opening(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_opening(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_opening(pid integer) OWNER TO postgres;

--
-- TOC entry 1552 (class 1255 OID 418709)
-- Name: del_opening(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_opening(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids int[] := '{}';
  surface_geometry_ids int[] := '{}';
  address_ids int[] := '{}';
BEGIN
  -- delete citydb.openings
  WITH delete_objects AS (
    DELETE FROM
      citydb.opening t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod3_implicit_rep_id,
      lod4_implicit_rep_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id,
      address_id
  )
  SELECT
    array_agg(id),
    array_agg(lod3_implicit_rep_id) ||
    array_agg(lod4_implicit_rep_id),
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id),
    array_agg(address_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids,
    address_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  -- delete citydb.address(s)
  IF -1 = ALL(address_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_address(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(address_ids) AS a_id) a
    LEFT JOIN
      citydb.address_to_bridge n1
      ON n1.address_id  = a.a_id
    LEFT JOIN
      citydb.address_to_building n2
      ON n2.address_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n3
      ON n3.address_id  = a.a_id
    LEFT JOIN
      citydb.opening n4
      ON n4.address_id  = a.a_id
    WHERE n1.address_id IS NULL
      AND n2.address_id IS NULL
      AND n3.address_id IS NULL
      AND n4.address_id IS NULL;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_opening(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1555 (class 1255 OID 418712)
-- Name: del_plant_cover(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_plant_cover(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_plant_cover(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_plant_cover(pid integer) OWNER TO postgres;

--
-- TOC entry 1554 (class 1255 OID 418711)
-- Name: del_plant_cover(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_plant_cover(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids int[] := '{}';
BEGIN
  -- delete citydb.plant_covers
  WITH delete_objects AS (
    DELETE FROM
      citydb.plant_cover t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod1_multi_surface_id,
      lod2_multi_surface_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id,
      lod1_multi_solid_id,
      lod2_multi_solid_id,
      lod3_multi_solid_id,
      lod4_multi_solid_id
  )
  SELECT
    array_agg(id),
    array_agg(lod1_multi_surface_id) ||
    array_agg(lod2_multi_surface_id) ||
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id) ||
    array_agg(lod1_multi_solid_id) ||
    array_agg(lod2_multi_solid_id) ||
    array_agg(lod3_multi_solid_id) ||
    array_agg(lod4_multi_solid_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_plant_cover(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1557 (class 1255 OID 418714)
-- Name: del_raster_relief(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_raster_relief(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_raster_relief(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_raster_relief(pid integer) OWNER TO postgres;

--
-- TOC entry 1556 (class 1255 OID 418713)
-- Name: del_raster_relief(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_raster_relief(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  grid_coverage_ids int[] := '{}';
BEGIN
  -- delete citydb.raster_reliefs
  WITH delete_objects AS (
    DELETE FROM
      citydb.raster_relief t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      coverage_id
  )
  SELECT
    array_agg(id),
    array_agg(coverage_id)
  INTO
    deleted_ids,
    grid_coverage_ids
  FROM
    delete_objects;

  -- delete citydb.grid_coverage(s)
  IF -1 = ALL(grid_coverage_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_grid_coverage(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(grid_coverage_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete relief_component
    PERFORM citydb.del_relief_component(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_raster_relief(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1559 (class 1255 OID 418716)
-- Name: del_relief_component(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_relief_component(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_relief_component(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_relief_component(pid integer) OWNER TO postgres;

--
-- TOC entry 1558 (class 1255 OID 418715)
-- Name: del_relief_component(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_relief_component(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
BEGIN
  IF $2 <> 2 THEN
    FOR rec IN
      SELECT
        co.id, co.objectclass_id
      FROM
        citydb.cityobject co, unnest($1) a(a_id)
      WHERE
        co.id = a.a_id
    LOOP
      object_id := rec.id::integer;
      objectclass_id := rec.objectclass_id::integer;
      CASE
        -- delete tin_relief
        WHEN objectclass_id = 16 THEN
          dummy_id := citydb.del_tin_relief(array_agg(object_id), 1);
        -- delete masspoint_relief
        WHEN objectclass_id = 17 THEN
          dummy_id := citydb.del_masspoint_relief(array_agg(object_id), 1);
        -- delete breakline_relief
        WHEN objectclass_id = 18 THEN
          dummy_id := citydb.del_breakline_relief(array_agg(object_id), 1);
        -- delete raster_relief
        WHEN objectclass_id = 19 THEN
          dummy_id := citydb.del_raster_relief(array_agg(object_id), 1);
        ELSE
          dummy_id := NULL;
      END CASE;

      IF dummy_id = object_id THEN
        deleted_child_ids := array_append(deleted_child_ids, dummy_id);
      END IF;
    END LOOP;
  END IF;

  -- delete citydb.relief_components
  WITH delete_objects AS (
    DELETE FROM
      citydb.relief_component t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_relief_component(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1561 (class 1255 OID 418718)
-- Name: del_relief_feature(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_relief_feature(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_relief_feature(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_relief_feature(pid integer) OWNER TO postgres;

--
-- TOC entry 1560 (class 1255 OID 418717)
-- Name: del_relief_feature(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_relief_feature(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  relief_component_ids int[] := '{}';
BEGIN
  -- delete references to relief_components
  WITH del_relief_component_refs AS (
    DELETE FROM
      citydb.relief_feat_to_rel_comp t
    USING
      unnest($1) a(a_id)
    WHERE
      t.relief_feature_id = a.a_id
    RETURNING
      t.relief_component_id
  )
  SELECT
    array_agg(relief_component_id)
  INTO
    relief_component_ids
  FROM
    del_relief_component_refs;

  -- delete citydb.relief_component(s)
  IF -1 = ALL(relief_component_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_relief_component(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(relief_component_ids) AS a_id) a
    LEFT JOIN
      citydb.relief_feat_to_rel_comp n1
      ON n1.relief_component_id  = a.a_id
    WHERE n1.relief_component_id IS NULL;
  END IF;

  -- delete citydb.relief_features
  WITH delete_objects AS (
    DELETE FROM
      citydb.relief_feature t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_relief_feature(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1563 (class 1255 OID 418720)
-- Name: del_room(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_room(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_room(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_room(pid integer) OWNER TO postgres;

--
-- TOC entry 1562 (class 1255 OID 418719)
-- Name: del_room(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_room(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids int[] := '{}';
BEGIN
  --delete building_furnitures
  PERFORM
    citydb.del_building_furniture(array_agg(t.id))
  FROM
    citydb.building_furniture t,
    unnest($1) a(a_id)
  WHERE
    t.room_id = a.a_id;

  --delete building_installations
  PERFORM
    citydb.del_building_installation(array_agg(t.id))
  FROM
    citydb.building_installation t,
    unnest($1) a(a_id)
  WHERE
    t.room_id = a.a_id;

  --delete thematic_surfaces
  PERFORM
    citydb.del_thematic_surface(array_agg(t.id))
  FROM
    citydb.thematic_surface t,
    unnest($1) a(a_id)
  WHERE
    t.room_id = a.a_id;

  -- delete citydb.rooms
  WITH delete_objects AS (
    DELETE FROM
      citydb.room t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod4_multi_surface_id,
      lod4_solid_id
  )
  SELECT
    array_agg(id),
    array_agg(lod4_multi_surface_id) ||
    array_agg(lod4_solid_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_room(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1565 (class 1255 OID 418722)
-- Name: del_solitary_vegetat_object(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_solitary_vegetat_object(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_solitary_vegetat_object(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_solitary_vegetat_object(pid integer) OWNER TO postgres;

--
-- TOC entry 1564 (class 1255 OID 418721)
-- Name: del_solitary_vegetat_object(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_solitary_vegetat_object(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids int[] := '{}';
  surface_geometry_ids int[] := '{}';
BEGIN
  -- delete citydb.solitary_vegetat_objects
  WITH delete_objects AS (
    DELETE FROM
      citydb.solitary_vegetat_object t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod1_implicit_rep_id,
      lod2_implicit_rep_id,
      lod3_implicit_rep_id,
      lod4_implicit_rep_id,
      lod1_brep_id,
      lod2_brep_id,
      lod3_brep_id,
      lod4_brep_id
  )
  SELECT
    array_agg(id),
    array_agg(lod1_implicit_rep_id) ||
    array_agg(lod2_implicit_rep_id) ||
    array_agg(lod3_implicit_rep_id) ||
    array_agg(lod4_implicit_rep_id),
    array_agg(lod1_brep_id) ||
    array_agg(lod2_brep_id) ||
    array_agg(lod3_brep_id) ||
    array_agg(lod4_brep_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_solitary_vegetat_object(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1567 (class 1255 OID 418724)
-- Name: del_surface_data(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_surface_data(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_surface_data(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_surface_data(pid integer) OWNER TO postgres;

--
-- TOC entry 1566 (class 1255 OID 418723)
-- Name: del_surface_data(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_surface_data(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  tex_image_ids int[] := '{}';
BEGIN
  -- delete citydb.surface_datas
  WITH delete_objects AS (
    DELETE FROM
      citydb.surface_data t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      tex_image_id
  )
  SELECT
    array_agg(id),
    array_agg(tex_image_id)
  INTO
    deleted_ids,
    tex_image_ids
  FROM
    delete_objects;

  -- delete citydb.tex_image(s)
  IF -1 = ALL(tex_image_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_tex_image(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(tex_image_ids) AS a_id) a
    LEFT JOIN
      citydb.surface_data n1
      ON n1.tex_image_id  = a.a_id
    WHERE n1.tex_image_id IS NULL;
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_surface_data(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1569 (class 1255 OID 418726)
-- Name: del_surface_geometry(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_surface_geometry(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_surface_geometry(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_surface_geometry(pid integer) OWNER TO postgres;

--
-- TOC entry 1568 (class 1255 OID 418725)
-- Name: del_surface_geometry(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_surface_geometry(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
BEGIN
  -- delete referenced parts
  PERFORM
    citydb.del_surface_geometry(array_agg(t.id))
  FROM
    citydb.surface_geometry t,
    unnest($1) a(a_id)
  WHERE
    t.parent_id = a.a_id
    AND t.id <> a.a_id;

  -- delete referenced parts
  PERFORM
    citydb.del_surface_geometry(array_agg(t.id))
  FROM
    citydb.surface_geometry t,
    unnest($1) a(a_id)
  WHERE
    t.root_id = a.a_id
    AND t.id <> a.a_id;

  -- delete citydb.surface_geometrys
  WITH delete_objects AS (
    DELETE FROM
      citydb.surface_geometry t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_surface_geometry(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1571 (class 1255 OID 418728)
-- Name: del_tex_image(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_tex_image(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_tex_image(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_tex_image(pid integer) OWNER TO postgres;

--
-- TOC entry 1570 (class 1255 OID 418727)
-- Name: del_tex_image(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_tex_image(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
BEGIN
  -- delete citydb.tex_images
  WITH delete_objects AS (
    DELETE FROM
      citydb.tex_image t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_tex_image(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1573 (class 1255 OID 418730)
-- Name: del_thematic_surface(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_thematic_surface(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_thematic_surface(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_thematic_surface(pid integer) OWNER TO postgres;

--
-- TOC entry 1572 (class 1255 OID 418729)
-- Name: del_thematic_surface(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_thematic_surface(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  opening_ids int[] := '{}';
  surface_geometry_ids int[] := '{}';
BEGIN
  -- delete references to openings
  WITH del_opening_refs AS (
    DELETE FROM
      citydb.opening_to_them_surface t
    USING
      unnest($1) a(a_id)
    WHERE
      t.thematic_surface_id = a.a_id
    RETURNING
      t.opening_id
  )
  SELECT
    array_agg(opening_id)
  INTO
    opening_ids
  FROM
    del_opening_refs;

  -- delete citydb.opening(s)
  IF -1 = ALL(opening_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_opening(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(opening_ids) AS a_id) a;
  END IF;

  -- delete citydb.thematic_surfaces
  WITH delete_objects AS (
    DELETE FROM
      citydb.thematic_surface t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod2_multi_surface_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id
  )
  SELECT
    array_agg(id),
    array_agg(lod2_multi_surface_id) ||
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_thematic_surface(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1575 (class 1255 OID 418732)
-- Name: del_tin_relief(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_tin_relief(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_tin_relief(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_tin_relief(pid integer) OWNER TO postgres;

--
-- TOC entry 1574 (class 1255 OID 418731)
-- Name: del_tin_relief(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_tin_relief(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids int[] := '{}';
BEGIN
  -- delete citydb.tin_reliefs
  WITH delete_objects AS (
    DELETE FROM
      citydb.tin_relief t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      surface_geometry_id
  )
  SELECT
    array_agg(id),
    array_agg(surface_geometry_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete relief_component
    PERFORM citydb.del_relief_component(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_tin_relief(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1577 (class 1255 OID 418734)
-- Name: del_traffic_area(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_traffic_area(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_traffic_area(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_traffic_area(pid integer) OWNER TO postgres;

--
-- TOC entry 1576 (class 1255 OID 418733)
-- Name: del_traffic_area(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_traffic_area(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids int[] := '{}';
BEGIN
  -- delete citydb.traffic_areas
  WITH delete_objects AS (
    DELETE FROM
      citydb.traffic_area t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod2_multi_surface_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id
  )
  SELECT
    array_agg(id),
    array_agg(lod2_multi_surface_id) ||
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_traffic_area(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1579 (class 1255 OID 418736)
-- Name: del_transportation_complex(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_transportation_complex(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_transportation_complex(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_transportation_complex(pid integer) OWNER TO postgres;

--
-- TOC entry 1578 (class 1255 OID 418735)
-- Name: del_transportation_complex(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_transportation_complex(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids int[] := '{}';
BEGIN
  --delete traffic_areas
  PERFORM
    citydb.del_traffic_area(array_agg(t.id))
  FROM
    citydb.traffic_area t,
    unnest($1) a(a_id)
  WHERE
    t.transportation_complex_id = a.a_id;

  -- delete citydb.transportation_complexs
  WITH delete_objects AS (
    DELETE FROM
      citydb.transportation_complex t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod1_multi_surface_id,
      lod2_multi_surface_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id
  )
  SELECT
    array_agg(id),
    array_agg(lod1_multi_surface_id) ||
    array_agg(lod2_multi_surface_id) ||
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_transportation_complex(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1581 (class 1255 OID 418738)
-- Name: del_tunnel(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_tunnel(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_tunnel(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_tunnel(pid integer) OWNER TO postgres;

--
-- TOC entry 1580 (class 1255 OID 418737)
-- Name: del_tunnel(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_tunnel(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids int[] := '{}';
BEGIN
  -- delete referenced parts
  PERFORM
    citydb.del_tunnel(array_agg(t.id))
  FROM
    citydb.tunnel t,
    unnest($1) a(a_id)
  WHERE
    t.tunnel_parent_id = a.a_id
    AND t.id <> a.a_id;

  -- delete referenced parts
  PERFORM
    citydb.del_tunnel(array_agg(t.id))
  FROM
    citydb.tunnel t,
    unnest($1) a(a_id)
  WHERE
    t.tunnel_root_id = a.a_id
    AND t.id <> a.a_id;

  --delete tunnel_hollow_spaces
  PERFORM
    citydb.del_tunnel_hollow_space(array_agg(t.id))
  FROM
    citydb.tunnel_hollow_space t,
    unnest($1) a(a_id)
  WHERE
    t.tunnel_id = a.a_id;

  --delete tunnel_installations
  PERFORM
    citydb.del_tunnel_installation(array_agg(t.id))
  FROM
    citydb.tunnel_installation t,
    unnest($1) a(a_id)
  WHERE
    t.tunnel_id = a.a_id;

  --delete tunnel_thematic_surfaces
  PERFORM
    citydb.del_tunnel_thematic_surface(array_agg(t.id))
  FROM
    citydb.tunnel_thematic_surface t,
    unnest($1) a(a_id)
  WHERE
    t.tunnel_id = a.a_id;

  -- delete citydb.tunnels
  WITH delete_objects AS (
    DELETE FROM
      citydb.tunnel t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod1_multi_surface_id,
      lod2_multi_surface_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id,
      lod1_solid_id,
      lod2_solid_id,
      lod3_solid_id,
      lod4_solid_id
  )
  SELECT
    array_agg(id),
    array_agg(lod1_multi_surface_id) ||
    array_agg(lod2_multi_surface_id) ||
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id) ||
    array_agg(lod1_solid_id) ||
    array_agg(lod2_solid_id) ||
    array_agg(lod3_solid_id) ||
    array_agg(lod4_solid_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_tunnel(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1583 (class 1255 OID 418740)
-- Name: del_tunnel_furniture(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_tunnel_furniture(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_tunnel_furniture(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_tunnel_furniture(pid integer) OWNER TO postgres;

--
-- TOC entry 1582 (class 1255 OID 418739)
-- Name: del_tunnel_furniture(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_tunnel_furniture(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids int[] := '{}';
  surface_geometry_ids int[] := '{}';
BEGIN
  -- delete citydb.tunnel_furnitures
  WITH delete_objects AS (
    DELETE FROM
      citydb.tunnel_furniture t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod4_implicit_rep_id,
      lod4_brep_id
  )
  SELECT
    array_agg(id),
    array_agg(lod4_implicit_rep_id),
    array_agg(lod4_brep_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_tunnel_furniture(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1585 (class 1255 OID 418742)
-- Name: del_tunnel_hollow_space(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_tunnel_hollow_space(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_tunnel_hollow_space(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_tunnel_hollow_space(pid integer) OWNER TO postgres;

--
-- TOC entry 1584 (class 1255 OID 418741)
-- Name: del_tunnel_hollow_space(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_tunnel_hollow_space(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids int[] := '{}';
BEGIN
  --delete tunnel_furnitures
  PERFORM
    citydb.del_tunnel_furniture(array_agg(t.id))
  FROM
    citydb.tunnel_furniture t,
    unnest($1) a(a_id)
  WHERE
    t.tunnel_hollow_space_id = a.a_id;

  --delete tunnel_installations
  PERFORM
    citydb.del_tunnel_installation(array_agg(t.id))
  FROM
    citydb.tunnel_installation t,
    unnest($1) a(a_id)
  WHERE
    t.tunnel_hollow_space_id = a.a_id;

  --delete tunnel_thematic_surfaces
  PERFORM
    citydb.del_tunnel_thematic_surface(array_agg(t.id))
  FROM
    citydb.tunnel_thematic_surface t,
    unnest($1) a(a_id)
  WHERE
    t.tunnel_hollow_space_id = a.a_id;

  -- delete citydb.tunnel_hollow_spaces
  WITH delete_objects AS (
    DELETE FROM
      citydb.tunnel_hollow_space t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod4_multi_surface_id,
      lod4_solid_id
  )
  SELECT
    array_agg(id),
    array_agg(lod4_multi_surface_id) ||
    array_agg(lod4_solid_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_tunnel_hollow_space(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1587 (class 1255 OID 418744)
-- Name: del_tunnel_installation(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_tunnel_installation(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_tunnel_installation(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_tunnel_installation(pid integer) OWNER TO postgres;

--
-- TOC entry 1586 (class 1255 OID 418743)
-- Name: del_tunnel_installation(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_tunnel_installation(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids int[] := '{}';
  surface_geometry_ids int[] := '{}';
BEGIN
  --delete tunnel_thematic_surfaces
  PERFORM
    citydb.del_tunnel_thematic_surface(array_agg(t.id))
  FROM
    citydb.tunnel_thematic_surface t,
    unnest($1) a(a_id)
  WHERE
    t.tunnel_installation_id = a.a_id;

  -- delete citydb.tunnel_installations
  WITH delete_objects AS (
    DELETE FROM
      citydb.tunnel_installation t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod2_implicit_rep_id,
      lod3_implicit_rep_id,
      lod4_implicit_rep_id,
      lod2_brep_id,
      lod3_brep_id,
      lod4_brep_id
  )
  SELECT
    array_agg(id),
    array_agg(lod2_implicit_rep_id) ||
    array_agg(lod3_implicit_rep_id) ||
    array_agg(lod4_implicit_rep_id),
    array_agg(lod2_brep_id) ||
    array_agg(lod3_brep_id) ||
    array_agg(lod4_brep_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_tunnel_installation(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1589 (class 1255 OID 418746)
-- Name: del_tunnel_opening(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_tunnel_opening(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_tunnel_opening(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_tunnel_opening(pid integer) OWNER TO postgres;

--
-- TOC entry 1588 (class 1255 OID 418745)
-- Name: del_tunnel_opening(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_tunnel_opening(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids int[] := '{}';
  surface_geometry_ids int[] := '{}';
BEGIN
  -- delete citydb.tunnel_openings
  WITH delete_objects AS (
    DELETE FROM
      citydb.tunnel_opening t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod3_implicit_rep_id,
      lod4_implicit_rep_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id
  )
  SELECT
    array_agg(id),
    array_agg(lod3_implicit_rep_id) ||
    array_agg(lod4_implicit_rep_id),
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_tunnel_opening(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1591 (class 1255 OID 418748)
-- Name: del_tunnel_thematic_surface(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_tunnel_thematic_surface(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_tunnel_thematic_surface(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_tunnel_thematic_surface(pid integer) OWNER TO postgres;

--
-- TOC entry 1590 (class 1255 OID 418747)
-- Name: del_tunnel_thematic_surface(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_tunnel_thematic_surface(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  tunnel_opening_ids int[] := '{}';
  surface_geometry_ids int[] := '{}';
BEGIN
  -- delete references to tunnel_openings
  WITH del_tunnel_opening_refs AS (
    DELETE FROM
      citydb.tunnel_open_to_them_srf t
    USING
      unnest($1) a(a_id)
    WHERE
      t.tunnel_thematic_surface_id = a.a_id
    RETURNING
      t.tunnel_opening_id
  )
  SELECT
    array_agg(tunnel_opening_id)
  INTO
    tunnel_opening_ids
  FROM
    del_tunnel_opening_refs;

  -- delete citydb.tunnel_opening(s)
  IF -1 = ALL(tunnel_opening_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_tunnel_opening(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(tunnel_opening_ids) AS a_id) a;
  END IF;

  -- delete citydb.tunnel_thematic_surfaces
  WITH delete_objects AS (
    DELETE FROM
      citydb.tunnel_thematic_surface t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod2_multi_surface_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id
  )
  SELECT
    array_agg(id),
    array_agg(lod2_multi_surface_id) ||
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_tunnel_thematic_surface(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1593 (class 1255 OID 418750)
-- Name: del_waterbody(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_waterbody(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_waterbody(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_waterbody(pid integer) OWNER TO postgres;

--
-- TOC entry 1592 (class 1255 OID 418749)
-- Name: del_waterbody(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_waterbody(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  waterboundary_surface_ids int[] := '{}';
  surface_geometry_ids int[] := '{}';
BEGIN
  -- delete references to waterboundary_surfaces
  WITH del_waterboundary_surface_refs AS (
    DELETE FROM
      citydb.waterbod_to_waterbnd_srf t
    USING
      unnest($1) a(a_id)
    WHERE
      t.waterbody_id = a.a_id
    RETURNING
      t.waterboundary_surface_id
  )
  SELECT
    array_agg(waterboundary_surface_id)
  INTO
    waterboundary_surface_ids
  FROM
    del_waterboundary_surface_refs;

  -- delete citydb.waterboundary_surface(s)
  IF -1 = ALL(waterboundary_surface_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_waterboundary_surface(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(waterboundary_surface_ids) AS a_id) a
    LEFT JOIN
      citydb.waterbod_to_waterbnd_srf n1
      ON n1.waterboundary_surface_id  = a.a_id
    WHERE n1.waterboundary_surface_id IS NULL;
  END IF;

  -- delete citydb.waterbodys
  WITH delete_objects AS (
    DELETE FROM
      citydb.waterbody t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod0_multi_surface_id,
      lod1_multi_surface_id,
      lod1_solid_id,
      lod2_solid_id,
      lod3_solid_id,
      lod4_solid_id
  )
  SELECT
    array_agg(id),
    array_agg(lod0_multi_surface_id) ||
    array_agg(lod1_multi_surface_id) ||
    array_agg(lod1_solid_id) ||
    array_agg(lod2_solid_id) ||
    array_agg(lod3_solid_id) ||
    array_agg(lod4_solid_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_waterbody(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1595 (class 1255 OID 418752)
-- Name: del_waterboundary_surface(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_waterboundary_surface(pid integer) RETURNS integer
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id integer;
BEGIN
  deleted_id := citydb.del_waterboundary_surface(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;


ALTER FUNCTION citydb.del_waterboundary_surface(pid integer) OWNER TO postgres;

--
-- TOC entry 1594 (class 1255 OID 418751)
-- Name: del_waterboundary_surface(integer[], integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.del_waterboundary_surface(integer[], caller integer DEFAULT 0) RETURNS SETOF integer
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids int[] := '{}';
  dummy_id integer;
  deleted_child_ids int[] := '{}';
  object_id integer;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids int[] := '{}';
BEGIN
  -- delete citydb.waterboundary_surfaces
  WITH delete_objects AS (
    DELETE FROM
      citydb.waterboundary_surface t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod2_surface_id,
      lod3_surface_id,
      lod4_surface_id
  )
  SELECT
    array_agg(id),
    array_agg(lod2_surface_id) ||
    array_agg(lod3_surface_id) ||
    array_agg(lod4_surface_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;


ALTER FUNCTION citydb.del_waterboundary_surface(integer[], caller integer) OWNER TO postgres;

--
-- TOC entry 1455 (class 1255 OID 418610)
-- Name: env_address(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_address(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- multiPoint
    SELECT multi_point AS geom FROM citydb.address WHERE id = co_id  AND multi_point IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_address(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1456 (class 1255 OID 418611)
-- Name: env_appearance(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_appearance(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _SurfaceData
    SELECT citydb.env_surface_data(c.id, set_envelope) AS geom FROM citydb.surface_data c, citydb.appear_to_surface_data p2c WHERE c.id = surface_data_id AND p2c.appearance_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_appearance(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1457 (class 1255 OID 418612)
-- Name: env_breakline_relief(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_breakline_relief(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_relief_component(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- ridgeOrValleyLines
    SELECT ridge_or_valley_lines AS geom FROM citydb.breakline_relief WHERE id = co_id  AND ridge_or_valley_lines IS NOT NULL
      UNION ALL
    -- breaklines
    SELECT break_lines AS geom FROM citydb.breakline_relief WHERE id = co_id  AND break_lines IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_breakline_relief(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1458 (class 1255 OID 418613)
-- Name: env_bridge(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_bridge(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod1Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge t WHERE sg.root_id = t.lod1_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge t WHERE sg.root_id = t.lod1_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1TerrainIntersection
    SELECT lod1_terrain_intersection AS geom FROM citydb.bridge WHERE id = co_id  AND lod1_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod2Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge t WHERE sg.root_id = t.lod2_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge t WHERE sg.root_id = t.lod2_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2MultiCurve
    SELECT lod2_multi_curve AS geom FROM citydb.bridge WHERE id = co_id  AND lod2_multi_curve IS NOT NULL
      UNION ALL
    -- lod2TerrainIntersection
    SELECT lod2_terrain_intersection AS geom FROM citydb.bridge WHERE id = co_id  AND lod2_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod3Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge t WHERE sg.root_id = t.lod3_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiCurve
    SELECT lod3_multi_curve AS geom FROM citydb.bridge WHERE id = co_id  AND lod3_multi_curve IS NOT NULL
      UNION ALL
    -- lod3TerrainIntersection
    SELECT lod3_terrain_intersection AS geom FROM citydb.bridge WHERE id = co_id  AND lod3_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod4Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge t WHERE sg.root_id = t.lod4_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiCurve
    SELECT lod4_multi_curve AS geom FROM citydb.bridge WHERE id = co_id  AND lod4_multi_curve IS NOT NULL
      UNION ALL
    -- lod4TerrainIntersection
    SELECT lod4_terrain_intersection AS geom FROM citydb.bridge WHERE id = co_id  AND lod4_terrain_intersection IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- BridgeConstructionElement
    SELECT citydb.env_bridge_constr_element(id, set_envelope) AS geom FROM citydb.bridge_constr_element WHERE bridge_id = co_id
      UNION ALL
    -- BridgeInstallation
    SELECT citydb.env_bridge_installation(id, set_envelope) AS geom FROM citydb.bridge_installation WHERE bridge_id = co_id
      UNION ALL
    -- IntBridgeInstallation
    SELECT citydb.env_bridge_installation(id, set_envelope) AS geom FROM citydb.bridge_installation WHERE bridge_id = co_id
      UNION ALL
    -- _BoundarySurface
    SELECT citydb.env_bridge_thematic_surface(id, set_envelope) AS geom FROM citydb.bridge_thematic_surface WHERE bridge_id = co_id
      UNION ALL
    -- BridgeRoom
    SELECT citydb.env_bridge_room(id, set_envelope) AS geom FROM citydb.bridge_room WHERE bridge_id = co_id
      UNION ALL
    -- BridgePart
    SELECT citydb.env_bridge(id, set_envelope) AS geom FROM citydb.bridge WHERE bridge_parent_id = co_id
      UNION ALL
    -- Address
    SELECT citydb.env_address(c.id, set_envelope) AS geom FROM citydb.address c, citydb.address_to_bridge p2c WHERE c.id = address_id AND p2c.bridge_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_bridge(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1459 (class 1255 OID 418614)
-- Name: env_bridge_constr_element(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_bridge_constr_element(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod1Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_constr_element t WHERE sg.root_id = t.lod1_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1Geometry
    SELECT lod1_other_geom AS geom FROM citydb.bridge_constr_element WHERE id = co_id  AND lod1_other_geom IS NOT NULL
      UNION ALL
    -- lod2Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_constr_element t WHERE sg.root_id = t.lod2_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2Geometry
    SELECT lod2_other_geom AS geom FROM citydb.bridge_constr_element WHERE id = co_id  AND lod2_other_geom IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_constr_element t WHERE sg.root_id = t.lod3_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT lod3_other_geom AS geom FROM citydb.bridge_constr_element WHERE id = co_id  AND lod3_other_geom IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_constr_element t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.bridge_constr_element WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod1TerrainIntersection
    SELECT lod1_terrain_intersection AS geom FROM citydb.bridge_constr_element WHERE id = co_id  AND lod1_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod2TerrainIntersection
    SELECT lod2_terrain_intersection AS geom FROM citydb.bridge_constr_element WHERE id = co_id  AND lod2_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod3TerrainIntersection
    SELECT lod3_terrain_intersection AS geom FROM citydb.bridge_constr_element WHERE id = co_id  AND lod3_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod4TerrainIntersection
    SELECT lod4_terrain_intersection AS geom FROM citydb.bridge_constr_element WHERE id = co_id  AND lod4_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod1ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod1_implicit_rep_id, lod1_implicit_ref_point, lod1_implicit_transformation) AS geom FROM citydb.bridge_constr_element WHERE id = co_id AND lod1_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod2ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod2_implicit_rep_id, lod2_implicit_ref_point, lod2_implicit_transformation) AS geom FROM citydb.bridge_constr_element WHERE id = co_id AND lod2_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod3ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod3_implicit_rep_id, lod3_implicit_ref_point, lod3_implicit_transformation) AS geom FROM citydb.bridge_constr_element WHERE id = co_id AND lod3_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.bridge_constr_element WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_bridge_constr_element(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1460 (class 1255 OID 418615)
-- Name: env_bridge_furniture(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_bridge_furniture(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_furniture t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.bridge_furniture WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.bridge_furniture WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_bridge_furniture(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1461 (class 1255 OID 418616)
-- Name: env_bridge_installation(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_bridge_installation(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod2Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_installation t WHERE sg.root_id = t.lod2_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2Geometry
    SELECT lod2_other_geom AS geom FROM citydb.bridge_installation WHERE id = co_id  AND lod2_other_geom IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_installation t WHERE sg.root_id = t.lod3_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT lod3_other_geom AS geom FROM citydb.bridge_installation WHERE id = co_id  AND lod3_other_geom IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_installation t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.bridge_installation WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod2ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod2_implicit_rep_id, lod2_implicit_ref_point, lod2_implicit_transformation) AS geom FROM citydb.bridge_installation WHERE id = co_id AND lod2_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod3ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod3_implicit_rep_id, lod3_implicit_ref_point, lod3_implicit_transformation) AS geom FROM citydb.bridge_installation WHERE id = co_id AND lod3_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.bridge_installation WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_installation t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.bridge_installation WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.bridge_installation WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _BoundarySurface
    SELECT citydb.env_bridge_thematic_surface(id, set_envelope) AS geom FROM citydb.bridge_thematic_surface WHERE bridge_installation_id = co_id
      UNION ALL
    -- _BoundarySurface
    SELECT citydb.env_bridge_thematic_surface(id, set_envelope) AS geom FROM citydb.bridge_thematic_surface WHERE bridge_installation_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_bridge_installation(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1462 (class 1255 OID 418617)
-- Name: env_bridge_opening(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_bridge_opening(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_opening t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_opening t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod3_implicit_rep_id, lod3_implicit_ref_point, lod3_implicit_transformation) AS geom FROM citydb.bridge_opening WHERE id = co_id AND lod3_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.bridge_opening WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- Address
    SELECT citydb.env_address(c.id, set_envelope) AS geom FROM citydb.bridge_opening p, address c WHERE p.id = co_id AND p.address_id = c.id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_bridge_opening(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1463 (class 1255 OID 418618)
-- Name: env_bridge_room(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_bridge_room(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod4Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_room t WHERE sg.root_id = t.lod4_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_room t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _BoundarySurface
    SELECT citydb.env_bridge_thematic_surface(id, set_envelope) AS geom FROM citydb.bridge_thematic_surface WHERE bridge_room_id = co_id
      UNION ALL
    -- BridgeFurniture
    SELECT citydb.env_bridge_furniture(id, set_envelope) AS geom FROM citydb.bridge_furniture WHERE bridge_room_id = co_id
      UNION ALL
    -- IntBridgeInstallation
    SELECT citydb.env_bridge_installation(id, set_envelope) AS geom FROM citydb.bridge_installation WHERE bridge_room_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_bridge_room(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1464 (class 1255 OID 418619)
-- Name: env_bridge_thematic_surface(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_bridge_thematic_surface(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod2MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_thematic_surface t WHERE sg.root_id = t.lod2_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_thematic_surface t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_thematic_surface t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _BridgeOpening
    SELECT citydb.env_bridge_opening(c.id, set_envelope) AS geom FROM citydb.bridge_opening c, citydb.bridge_open_to_them_srf p2c WHERE c.id = bridge_opening_id AND p2c.bridge_thematic_surface_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_bridge_thematic_surface(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1465 (class 1255 OID 418620)
-- Name: env_building(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_building(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod0FootPrint
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building t WHERE sg.root_id = t.lod0_footprint_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod0RoofEdge
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building t WHERE sg.root_id = t.lod0_roofprint_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building t WHERE sg.root_id = t.lod1_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building t WHERE sg.root_id = t.lod1_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1TerrainIntersection
    SELECT lod1_terrain_intersection AS geom FROM citydb.building WHERE id = co_id  AND lod1_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod2Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building t WHERE sg.root_id = t.lod2_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building t WHERE sg.root_id = t.lod2_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2MultiCurve
    SELECT lod2_multi_curve AS geom FROM citydb.building WHERE id = co_id  AND lod2_multi_curve IS NOT NULL
      UNION ALL
    -- lod2TerrainIntersection
    SELECT lod2_terrain_intersection AS geom FROM citydb.building WHERE id = co_id  AND lod2_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod3Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building t WHERE sg.root_id = t.lod3_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiCurve
    SELECT lod3_multi_curve AS geom FROM citydb.building WHERE id = co_id  AND lod3_multi_curve IS NOT NULL
      UNION ALL
    -- lod3TerrainIntersection
    SELECT lod3_terrain_intersection AS geom FROM citydb.building WHERE id = co_id  AND lod3_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod4Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building t WHERE sg.root_id = t.lod4_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiCurve
    SELECT lod4_multi_curve AS geom FROM citydb.building WHERE id = co_id  AND lod4_multi_curve IS NOT NULL
      UNION ALL
    -- lod4TerrainIntersection
    SELECT lod4_terrain_intersection AS geom FROM citydb.building WHERE id = co_id  AND lod4_terrain_intersection IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- BuildingInstallation
    SELECT citydb.env_building_installation(id, set_envelope) AS geom FROM citydb.building_installation WHERE building_id = co_id
      UNION ALL
    -- IntBuildingInstallation
    SELECT citydb.env_building_installation(id, set_envelope) AS geom FROM citydb.building_installation WHERE building_id = co_id
      UNION ALL
    -- _BoundarySurface
    SELECT citydb.env_thematic_surface(id, set_envelope) AS geom FROM citydb.thematic_surface WHERE building_id = co_id
      UNION ALL
    -- Room
    SELECT citydb.env_room(id, set_envelope) AS geom FROM citydb.room WHERE building_id = co_id
      UNION ALL
    -- BuildingPart
    SELECT citydb.env_building(id, set_envelope) AS geom FROM citydb.building WHERE building_parent_id = co_id
      UNION ALL
    -- Address
    SELECT citydb.env_address(c.id, set_envelope) AS geom FROM citydb.address c, citydb.address_to_building p2c WHERE c.id = address_id AND p2c.building_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_building(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1466 (class 1255 OID 418621)
-- Name: env_building_furniture(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_building_furniture(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building_furniture t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.building_furniture WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.building_furniture WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_building_furniture(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1467 (class 1255 OID 418622)
-- Name: env_building_installation(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_building_installation(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod2Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building_installation t WHERE sg.root_id = t.lod2_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2Geometry
    SELECT lod2_other_geom AS geom FROM citydb.building_installation WHERE id = co_id  AND lod2_other_geom IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building_installation t WHERE sg.root_id = t.lod3_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT lod3_other_geom AS geom FROM citydb.building_installation WHERE id = co_id  AND lod3_other_geom IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building_installation t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.building_installation WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod2ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod2_implicit_rep_id, lod2_implicit_ref_point, lod2_implicit_transformation) AS geom FROM citydb.building_installation WHERE id = co_id AND lod2_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod3ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod3_implicit_rep_id, lod3_implicit_ref_point, lod3_implicit_transformation) AS geom FROM citydb.building_installation WHERE id = co_id AND lod3_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.building_installation WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building_installation t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.building_installation WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.building_installation WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _BoundarySurface
    SELECT citydb.env_thematic_surface(id, set_envelope) AS geom FROM citydb.thematic_surface WHERE building_installation_id = co_id
      UNION ALL
    -- _BoundarySurface
    SELECT citydb.env_thematic_surface(id, set_envelope) AS geom FROM citydb.thematic_surface WHERE building_installation_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_building_installation(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1468 (class 1255 OID 418623)
-- Name: env_city_furniture(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_city_furniture(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod1Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.city_furniture t WHERE sg.root_id = t.lod1_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1Geometry
    SELECT lod1_other_geom AS geom FROM citydb.city_furniture WHERE id = co_id  AND lod1_other_geom IS NOT NULL
      UNION ALL
    -- lod2Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.city_furniture t WHERE sg.root_id = t.lod2_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2Geometry
    SELECT lod2_other_geom AS geom FROM citydb.city_furniture WHERE id = co_id  AND lod2_other_geom IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.city_furniture t WHERE sg.root_id = t.lod3_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT lod3_other_geom AS geom FROM citydb.city_furniture WHERE id = co_id  AND lod3_other_geom IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.city_furniture t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.city_furniture WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod1TerrainIntersection
    SELECT lod1_terrain_intersection AS geom FROM citydb.city_furniture WHERE id = co_id  AND lod1_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod2TerrainIntersection
    SELECT lod2_terrain_intersection AS geom FROM citydb.city_furniture WHERE id = co_id  AND lod2_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod3TerrainIntersection
    SELECT lod3_terrain_intersection AS geom FROM citydb.city_furniture WHERE id = co_id  AND lod3_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod4TerrainIntersection
    SELECT lod4_terrain_intersection AS geom FROM citydb.city_furniture WHERE id = co_id  AND lod4_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod1ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod1_implicit_rep_id, lod1_implicit_ref_point, lod1_implicit_transformation) AS geom FROM citydb.city_furniture WHERE id = co_id AND lod1_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod2ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod2_implicit_rep_id, lod2_implicit_ref_point, lod2_implicit_transformation) AS geom FROM citydb.city_furniture WHERE id = co_id AND lod2_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod3ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod3_implicit_rep_id, lod3_implicit_ref_point, lod3_implicit_transformation) AS geom FROM citydb.city_furniture WHERE id = co_id AND lod3_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.city_furniture WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_city_furniture(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1469 (class 1255 OID 418624)
-- Name: env_citymodel(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_citymodel(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_citymodel(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1470 (class 1255 OID 418625)
-- Name: env_cityobject(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_cityobject(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- Appearance
    SELECT citydb.env_appearance(id, set_envelope) AS geom FROM citydb.appearance WHERE cityobject_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  IF caller <> 2 THEN
    SELECT objectclass_id INTO class_id FROM citydb.cityobject WHERE id = co_id;
    CASE
      -- land_use
      WHEN class_id = 4 THEN
        dummy_bbox := citydb.env_land_use(co_id, set_envelope, 1);
      -- generic_cityobject
      WHEN class_id = 5 THEN
        dummy_bbox := citydb.env_generic_cityobject(co_id, set_envelope, 1);
      -- solitary_vegetat_object
      WHEN class_id = 7 THEN
        dummy_bbox := citydb.env_solitary_vegetat_object(co_id, set_envelope, 1);
      -- plant_cover
      WHEN class_id = 8 THEN
        dummy_bbox := citydb.env_plant_cover(co_id, set_envelope, 1);
      -- waterbody
      WHEN class_id = 9 THEN
        dummy_bbox := citydb.env_waterbody(co_id, set_envelope, 1);
      -- waterboundary_surface
      WHEN class_id = 10 THEN
        dummy_bbox := citydb.env_waterboundary_surface(co_id, set_envelope, 1);
      -- waterboundary_surface
      WHEN class_id = 11 THEN
        dummy_bbox := citydb.env_waterboundary_surface(co_id, set_envelope, 1);
      -- waterboundary_surface
      WHEN class_id = 12 THEN
        dummy_bbox := citydb.env_waterboundary_surface(co_id, set_envelope, 1);
      -- waterboundary_surface
      WHEN class_id = 13 THEN
        dummy_bbox := citydb.env_waterboundary_surface(co_id, set_envelope, 1);
      -- relief_feature
      WHEN class_id = 14 THEN
        dummy_bbox := citydb.env_relief_feature(co_id, set_envelope, 1);
      -- relief_component
      WHEN class_id = 15 THEN
        dummy_bbox := citydb.env_relief_component(co_id, set_envelope, 1);
      -- tin_relief
      WHEN class_id = 16 THEN
        dummy_bbox := citydb.env_tin_relief(co_id, set_envelope, 0);
      -- masspoint_relief
      WHEN class_id = 17 THEN
        dummy_bbox := citydb.env_masspoint_relief(co_id, set_envelope, 0);
      -- breakline_relief
      WHEN class_id = 18 THEN
        dummy_bbox := citydb.env_breakline_relief(co_id, set_envelope, 0);
      -- raster_relief
      WHEN class_id = 19 THEN
        dummy_bbox := citydb.env_raster_relief(co_id, set_envelope, 0);
      -- city_furniture
      WHEN class_id = 21 THEN
        dummy_bbox := citydb.env_city_furniture(co_id, set_envelope, 1);
      -- cityobjectgroup
      WHEN class_id = 23 THEN
        dummy_bbox := citydb.env_cityobjectgroup(co_id, set_envelope, 1);
      -- building
      WHEN class_id = 24 THEN
        dummy_bbox := citydb.env_building(co_id, set_envelope, 1);
      -- building
      WHEN class_id = 25 THEN
        dummy_bbox := citydb.env_building(co_id, set_envelope, 1);
      -- building
      WHEN class_id = 26 THEN
        dummy_bbox := citydb.env_building(co_id, set_envelope, 1);
      -- building_installation
      WHEN class_id = 27 THEN
        dummy_bbox := citydb.env_building_installation(co_id, set_envelope, 1);
      -- building_installation
      WHEN class_id = 28 THEN
        dummy_bbox := citydb.env_building_installation(co_id, set_envelope, 1);
      -- thematic_surface
      WHEN class_id = 29 THEN
        dummy_bbox := citydb.env_thematic_surface(co_id, set_envelope, 1);
      -- thematic_surface
      WHEN class_id = 30 THEN
        dummy_bbox := citydb.env_thematic_surface(co_id, set_envelope, 1);
      -- thematic_surface
      WHEN class_id = 31 THEN
        dummy_bbox := citydb.env_thematic_surface(co_id, set_envelope, 1);
      -- thematic_surface
      WHEN class_id = 32 THEN
        dummy_bbox := citydb.env_thematic_surface(co_id, set_envelope, 1);
      -- thematic_surface
      WHEN class_id = 33 THEN
        dummy_bbox := citydb.env_thematic_surface(co_id, set_envelope, 1);
      -- thematic_surface
      WHEN class_id = 34 THEN
        dummy_bbox := citydb.env_thematic_surface(co_id, set_envelope, 1);
      -- thematic_surface
      WHEN class_id = 35 THEN
        dummy_bbox := citydb.env_thematic_surface(co_id, set_envelope, 1);
      -- thematic_surface
      WHEN class_id = 36 THEN
        dummy_bbox := citydb.env_thematic_surface(co_id, set_envelope, 1);
      -- opening
      WHEN class_id = 37 THEN
        dummy_bbox := citydb.env_opening(co_id, set_envelope, 1);
      -- opening
      WHEN class_id = 38 THEN
        dummy_bbox := citydb.env_opening(co_id, set_envelope, 1);
      -- opening
      WHEN class_id = 39 THEN
        dummy_bbox := citydb.env_opening(co_id, set_envelope, 1);
      -- building_furniture
      WHEN class_id = 40 THEN
        dummy_bbox := citydb.env_building_furniture(co_id, set_envelope, 1);
      -- room
      WHEN class_id = 41 THEN
        dummy_bbox := citydb.env_room(co_id, set_envelope, 1);
      -- transportation_complex
      WHEN class_id = 42 THEN
        dummy_bbox := citydb.env_transportation_complex(co_id, set_envelope, 1);
      -- transportation_complex
      WHEN class_id = 43 THEN
        dummy_bbox := citydb.env_transportation_complex(co_id, set_envelope, 1);
      -- transportation_complex
      WHEN class_id = 44 THEN
        dummy_bbox := citydb.env_transportation_complex(co_id, set_envelope, 1);
      -- transportation_complex
      WHEN class_id = 45 THEN
        dummy_bbox := citydb.env_transportation_complex(co_id, set_envelope, 1);
      -- transportation_complex
      WHEN class_id = 46 THEN
        dummy_bbox := citydb.env_transportation_complex(co_id, set_envelope, 1);
      -- traffic_area
      WHEN class_id = 47 THEN
        dummy_bbox := citydb.env_traffic_area(co_id, set_envelope, 1);
      -- traffic_area
      WHEN class_id = 48 THEN
        dummy_bbox := citydb.env_traffic_area(co_id, set_envelope, 1);
      -- appearance
      WHEN class_id = 50 THEN
        dummy_bbox := citydb.env_appearance(co_id, set_envelope, 0);
      -- surface_data
      WHEN class_id = 51 THEN
        dummy_bbox := citydb.env_surface_data(co_id, set_envelope, 0);
      -- surface_data
      WHEN class_id = 52 THEN
        dummy_bbox := citydb.env_surface_data(co_id, set_envelope, 0);
      -- surface_data
      WHEN class_id = 53 THEN
        dummy_bbox := citydb.env_surface_data(co_id, set_envelope, 0);
      -- surface_data
      WHEN class_id = 54 THEN
        dummy_bbox := citydb.env_surface_data(co_id, set_envelope, 0);
      -- surface_data
      WHEN class_id = 55 THEN
        dummy_bbox := citydb.env_surface_data(co_id, set_envelope, 0);
      -- textureparam
      WHEN class_id = 56 THEN
        dummy_bbox := citydb.env_textureparam(co_id, set_envelope, 0);
      -- citymodel
      WHEN class_id = 57 THEN
        dummy_bbox := citydb.env_citymodel(co_id, set_envelope, 0);
      -- address
      WHEN class_id = 58 THEN
        dummy_bbox := citydb.env_address(co_id, set_envelope, 0);
      -- implicit_geometry
      WHEN class_id = 59 THEN
        dummy_bbox := citydb.env_implicit_geometry(co_id, set_envelope, 0);
      -- thematic_surface
      WHEN class_id = 60 THEN
        dummy_bbox := citydb.env_thematic_surface(co_id, set_envelope, 1);
      -- thematic_surface
      WHEN class_id = 61 THEN
        dummy_bbox := citydb.env_thematic_surface(co_id, set_envelope, 1);
      -- bridge
      WHEN class_id = 62 THEN
        dummy_bbox := citydb.env_bridge(co_id, set_envelope, 1);
      -- bridge
      WHEN class_id = 63 THEN
        dummy_bbox := citydb.env_bridge(co_id, set_envelope, 1);
      -- bridge
      WHEN class_id = 64 THEN
        dummy_bbox := citydb.env_bridge(co_id, set_envelope, 1);
      -- bridge_installation
      WHEN class_id = 65 THEN
        dummy_bbox := citydb.env_bridge_installation(co_id, set_envelope, 1);
      -- bridge_installation
      WHEN class_id = 66 THEN
        dummy_bbox := citydb.env_bridge_installation(co_id, set_envelope, 1);
      -- bridge_thematic_surface
      WHEN class_id = 67 THEN
        dummy_bbox := citydb.env_bridge_thematic_surface(co_id, set_envelope, 1);
      -- bridge_thematic_surface
      WHEN class_id = 68 THEN
        dummy_bbox := citydb.env_bridge_thematic_surface(co_id, set_envelope, 1);
      -- bridge_thematic_surface
      WHEN class_id = 69 THEN
        dummy_bbox := citydb.env_bridge_thematic_surface(co_id, set_envelope, 1);
      -- bridge_thematic_surface
      WHEN class_id = 70 THEN
        dummy_bbox := citydb.env_bridge_thematic_surface(co_id, set_envelope, 1);
      -- bridge_thematic_surface
      WHEN class_id = 71 THEN
        dummy_bbox := citydb.env_bridge_thematic_surface(co_id, set_envelope, 1);
      -- bridge_thematic_surface
      WHEN class_id = 72 THEN
        dummy_bbox := citydb.env_bridge_thematic_surface(co_id, set_envelope, 1);
      -- bridge_thematic_surface
      WHEN class_id = 73 THEN
        dummy_bbox := citydb.env_bridge_thematic_surface(co_id, set_envelope, 1);
      -- bridge_thematic_surface
      WHEN class_id = 74 THEN
        dummy_bbox := citydb.env_bridge_thematic_surface(co_id, set_envelope, 1);
      -- bridge_thematic_surface
      WHEN class_id = 75 THEN
        dummy_bbox := citydb.env_bridge_thematic_surface(co_id, set_envelope, 1);
      -- bridge_thematic_surface
      WHEN class_id = 76 THEN
        dummy_bbox := citydb.env_bridge_thematic_surface(co_id, set_envelope, 1);
      -- bridge_opening
      WHEN class_id = 77 THEN
        dummy_bbox := citydb.env_bridge_opening(co_id, set_envelope, 1);
      -- bridge_opening
      WHEN class_id = 78 THEN
        dummy_bbox := citydb.env_bridge_opening(co_id, set_envelope, 1);
      -- bridge_opening
      WHEN class_id = 79 THEN
        dummy_bbox := citydb.env_bridge_opening(co_id, set_envelope, 1);
      -- bridge_furniture
      WHEN class_id = 80 THEN
        dummy_bbox := citydb.env_bridge_furniture(co_id, set_envelope, 1);
      -- bridge_room
      WHEN class_id = 81 THEN
        dummy_bbox := citydb.env_bridge_room(co_id, set_envelope, 1);
      -- bridge_constr_element
      WHEN class_id = 82 THEN
        dummy_bbox := citydb.env_bridge_constr_element(co_id, set_envelope, 1);
      -- tunnel
      WHEN class_id = 83 THEN
        dummy_bbox := citydb.env_tunnel(co_id, set_envelope, 1);
      -- tunnel
      WHEN class_id = 84 THEN
        dummy_bbox := citydb.env_tunnel(co_id, set_envelope, 1);
      -- tunnel
      WHEN class_id = 85 THEN
        dummy_bbox := citydb.env_tunnel(co_id, set_envelope, 1);
      -- tunnel_installation
      WHEN class_id = 86 THEN
        dummy_bbox := citydb.env_tunnel_installation(co_id, set_envelope, 1);
      -- tunnel_installation
      WHEN class_id = 87 THEN
        dummy_bbox := citydb.env_tunnel_installation(co_id, set_envelope, 1);
      -- tunnel_thematic_surface
      WHEN class_id = 88 THEN
        dummy_bbox := citydb.env_tunnel_thematic_surface(co_id, set_envelope, 1);
      -- tunnel_thematic_surface
      WHEN class_id = 89 THEN
        dummy_bbox := citydb.env_tunnel_thematic_surface(co_id, set_envelope, 1);
      -- tunnel_thematic_surface
      WHEN class_id = 90 THEN
        dummy_bbox := citydb.env_tunnel_thematic_surface(co_id, set_envelope, 1);
      -- tunnel_thematic_surface
      WHEN class_id = 91 THEN
        dummy_bbox := citydb.env_tunnel_thematic_surface(co_id, set_envelope, 1);
      -- tunnel_thematic_surface
      WHEN class_id = 92 THEN
        dummy_bbox := citydb.env_tunnel_thematic_surface(co_id, set_envelope, 1);
      -- tunnel_thematic_surface
      WHEN class_id = 93 THEN
        dummy_bbox := citydb.env_tunnel_thematic_surface(co_id, set_envelope, 1);
      -- tunnel_thematic_surface
      WHEN class_id = 94 THEN
        dummy_bbox := citydb.env_tunnel_thematic_surface(co_id, set_envelope, 1);
      -- tunnel_thematic_surface
      WHEN class_id = 95 THEN
        dummy_bbox := citydb.env_tunnel_thematic_surface(co_id, set_envelope, 1);
      -- tunnel_thematic_surface
      WHEN class_id = 96 THEN
        dummy_bbox := citydb.env_tunnel_thematic_surface(co_id, set_envelope, 1);
      -- tunnel_thematic_surface
      WHEN class_id = 97 THEN
        dummy_bbox := citydb.env_tunnel_thematic_surface(co_id, set_envelope, 1);
      -- tunnel_opening
      WHEN class_id = 98 THEN
        dummy_bbox := citydb.env_tunnel_opening(co_id, set_envelope, 1);
      -- tunnel_opening
      WHEN class_id = 99 THEN
        dummy_bbox := citydb.env_tunnel_opening(co_id, set_envelope, 1);
      -- tunnel_opening
      WHEN class_id = 100 THEN
        dummy_bbox := citydb.env_tunnel_opening(co_id, set_envelope, 1);
      -- tunnel_furniture
      WHEN class_id = 101 THEN
        dummy_bbox := citydb.env_tunnel_furniture(co_id, set_envelope, 1);
      -- tunnel_hollow_space
      WHEN class_id = 102 THEN
        dummy_bbox := citydb.env_tunnel_hollow_space(co_id, set_envelope, 1);
      -- textureparam
      WHEN class_id = 103 THEN
        dummy_bbox := citydb.env_textureparam(co_id, set_envelope, 0);
      -- textureparam
      WHEN class_id = 104 THEN
        dummy_bbox := citydb.env_textureparam(co_id, set_envelope, 0);
      ELSE
    END CASE;
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  IF set_envelope <> 0 THEN
    UPDATE citydb.cityobject SET envelope = bbox WHERE id = co_id;
  END IF;

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_cityobject(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1471 (class 1255 OID 418627)
-- Name: env_cityobjectgroup(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_cityobjectgroup(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.cityobjectgroup t WHERE sg.root_id = t.brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- geometry
    SELECT other_geom AS geom FROM citydb.cityobjectgroup WHERE id = co_id  AND other_geom IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _CityObject
    SELECT citydb.env_cityobject(c.id, set_envelope) AS geom FROM citydb.cityobject c, citydb.group_to_cityobject p2c WHERE c.id = cityobject_id AND p2c.cityobjectgroup_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_cityobjectgroup(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1472 (class 1255 OID 418628)
-- Name: env_generic_cityobject(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_generic_cityobject(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod0Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.generic_cityobject t WHERE sg.root_id = t.lod0_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod0Geometry
    SELECT lod0_other_geom AS geom FROM citydb.generic_cityobject WHERE id = co_id  AND lod0_other_geom IS NOT NULL
      UNION ALL
    -- lod1Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.generic_cityobject t WHERE sg.root_id = t.lod1_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1Geometry
    SELECT lod1_other_geom AS geom FROM citydb.generic_cityobject WHERE id = co_id  AND lod1_other_geom IS NOT NULL
      UNION ALL
    -- lod2Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.generic_cityobject t WHERE sg.root_id = t.lod2_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2Geometry
    SELECT lod2_other_geom AS geom FROM citydb.generic_cityobject WHERE id = co_id  AND lod2_other_geom IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.generic_cityobject t WHERE sg.root_id = t.lod3_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT lod3_other_geom AS geom FROM citydb.generic_cityobject WHERE id = co_id  AND lod3_other_geom IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.generic_cityobject t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.generic_cityobject WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod0TerrainIntersection
    SELECT lod0_terrain_intersection AS geom FROM citydb.generic_cityobject WHERE id = co_id  AND lod0_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod1TerrainIntersection
    SELECT lod1_terrain_intersection AS geom FROM citydb.generic_cityobject WHERE id = co_id  AND lod1_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod2TerrainIntersection
    SELECT lod2_terrain_intersection AS geom FROM citydb.generic_cityobject WHERE id = co_id  AND lod2_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod3TerrainIntersection
    SELECT lod3_terrain_intersection AS geom FROM citydb.generic_cityobject WHERE id = co_id  AND lod3_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod4TerrainIntersection
    SELECT lod4_terrain_intersection AS geom FROM citydb.generic_cityobject WHERE id = co_id  AND lod4_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod0ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod0_implicit_rep_id, lod0_implicit_ref_point, lod0_implicit_transformation) AS geom FROM citydb.generic_cityobject WHERE id = co_id AND lod0_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod1ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod1_implicit_rep_id, lod1_implicit_ref_point, lod1_implicit_transformation) AS geom FROM citydb.generic_cityobject WHERE id = co_id AND lod1_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod2ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod2_implicit_rep_id, lod2_implicit_ref_point, lod2_implicit_transformation) AS geom FROM citydb.generic_cityobject WHERE id = co_id AND lod2_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod3ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod3_implicit_rep_id, lod3_implicit_ref_point, lod3_implicit_transformation) AS geom FROM citydb.generic_cityobject WHERE id = co_id AND lod3_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.generic_cityobject WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_generic_cityobject(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1473 (class 1255 OID 418629)
-- Name: env_implicit_geometry(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_implicit_geometry(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_implicit_geometry(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1474 (class 1255 OID 418630)
-- Name: env_land_use(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_land_use(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod0MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.land_use t WHERE sg.root_id = t.lod0_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.land_use t WHERE sg.root_id = t.lod1_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.land_use t WHERE sg.root_id = t.lod2_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.land_use t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.land_use t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_land_use(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1475 (class 1255 OID 418631)
-- Name: env_masspoint_relief(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_masspoint_relief(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_relief_component(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- reliefPoints
    SELECT relief_points AS geom FROM citydb.masspoint_relief WHERE id = co_id  AND relief_points IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_masspoint_relief(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1476 (class 1255 OID 418632)
-- Name: env_opening(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_opening(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.opening t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.opening t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod3_implicit_rep_id, lod3_implicit_ref_point, lod3_implicit_transformation) AS geom FROM citydb.opening WHERE id = co_id AND lod3_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.opening WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- Address
    SELECT citydb.env_address(c.id, set_envelope) AS geom FROM citydb.opening p, address c WHERE p.id = co_id AND p.address_id = c.id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_opening(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1477 (class 1255 OID 418633)
-- Name: env_plant_cover(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_plant_cover(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod1MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.plant_cover t WHERE sg.root_id = t.lod1_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.plant_cover t WHERE sg.root_id = t.lod2_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.plant_cover t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.plant_cover t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1MultiSolid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.plant_cover t WHERE sg.root_id = t.lod1_multi_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2MultiSolid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.plant_cover t WHERE sg.root_id = t.lod2_multi_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSolid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.plant_cover t WHERE sg.root_id = t.lod3_multi_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSolid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.plant_cover t WHERE sg.root_id = t.lod4_multi_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_plant_cover(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1478 (class 1255 OID 418634)
-- Name: env_raster_relief(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_raster_relief(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_relief_component(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_raster_relief(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1479 (class 1255 OID 418635)
-- Name: env_relief_component(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_relief_component(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- extent
    SELECT extent AS geom FROM citydb.relief_component WHERE id = co_id  AND extent IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  IF caller <> 2 THEN
    SELECT objectclass_id INTO class_id FROM citydb.relief_component WHERE id = co_id;
    CASE
      -- tin_relief
      WHEN class_id = 16 THEN
        dummy_bbox := citydb.env_tin_relief(co_id, set_envelope, 1);
      -- masspoint_relief
      WHEN class_id = 17 THEN
        dummy_bbox := citydb.env_masspoint_relief(co_id, set_envelope, 1);
      -- breakline_relief
      WHEN class_id = 18 THEN
        dummy_bbox := citydb.env_breakline_relief(co_id, set_envelope, 1);
      -- raster_relief
      WHEN class_id = 19 THEN
        dummy_bbox := citydb.env_raster_relief(co_id, set_envelope, 1);
      ELSE
    END CASE;
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_relief_component(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1480 (class 1255 OID 418636)
-- Name: env_relief_feature(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_relief_feature(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _ReliefComponent
    SELECT citydb.env_relief_component(c.id, set_envelope) AS geom FROM citydb.relief_component c, citydb.relief_feat_to_rel_comp p2c WHERE c.id = relief_component_id AND p2c.relief_feature_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_relief_feature(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1481 (class 1255 OID 418637)
-- Name: env_room(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_room(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod4Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.room t WHERE sg.root_id = t.lod4_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.room t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _BoundarySurface
    SELECT citydb.env_thematic_surface(id, set_envelope) AS geom FROM citydb.thematic_surface WHERE room_id = co_id
      UNION ALL
    -- BuildingFurniture
    SELECT citydb.env_building_furniture(id, set_envelope) AS geom FROM citydb.building_furniture WHERE room_id = co_id
      UNION ALL
    -- IntBuildingInstallation
    SELECT citydb.env_building_installation(id, set_envelope) AS geom FROM citydb.building_installation WHERE room_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_room(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1482 (class 1255 OID 418638)
-- Name: env_solitary_vegetat_object(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_solitary_vegetat_object(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod1Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.solitary_vegetat_object t WHERE sg.root_id = t.lod1_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1Geometry
    SELECT lod1_other_geom AS geom FROM citydb.solitary_vegetat_object WHERE id = co_id  AND lod1_other_geom IS NOT NULL
      UNION ALL
    -- lod2Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.solitary_vegetat_object t WHERE sg.root_id = t.lod2_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2Geometry
    SELECT lod2_other_geom AS geom FROM citydb.solitary_vegetat_object WHERE id = co_id  AND lod2_other_geom IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.solitary_vegetat_object t WHERE sg.root_id = t.lod3_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT lod3_other_geom AS geom FROM citydb.solitary_vegetat_object WHERE id = co_id  AND lod3_other_geom IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.solitary_vegetat_object t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.solitary_vegetat_object WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod1ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod1_implicit_rep_id, lod1_implicit_ref_point, lod1_implicit_transformation) AS geom FROM citydb.solitary_vegetat_object WHERE id = co_id AND lod1_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod2ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod2_implicit_rep_id, lod2_implicit_ref_point, lod2_implicit_transformation) AS geom FROM citydb.solitary_vegetat_object WHERE id = co_id AND lod2_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod3ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod3_implicit_rep_id, lod3_implicit_ref_point, lod3_implicit_transformation) AS geom FROM citydb.solitary_vegetat_object WHERE id = co_id AND lod3_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.solitary_vegetat_object WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_solitary_vegetat_object(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1483 (class 1255 OID 418639)
-- Name: env_surface_data(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_surface_data(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- referencePoint
    SELECT gt_reference_point AS geom FROM citydb.surface_data WHERE id = co_id  AND gt_reference_point IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_surface_data(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1484 (class 1255 OID 418640)
-- Name: env_textureparam(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_textureparam(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_textureparam(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1485 (class 1255 OID 418641)
-- Name: env_thematic_surface(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_thematic_surface(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod2MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.thematic_surface t WHERE sg.root_id = t.lod2_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.thematic_surface t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.thematic_surface t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _Opening
    SELECT citydb.env_opening(c.id, set_envelope) AS geom FROM citydb.opening c, citydb.opening_to_them_surface p2c WHERE c.id = opening_id AND p2c.thematic_surface_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_thematic_surface(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1486 (class 1255 OID 418642)
-- Name: env_tin_relief(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_tin_relief(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_relief_component(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- tin
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tin_relief t WHERE sg.root_id = t.surface_geometry_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_tin_relief(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1487 (class 1255 OID 418643)
-- Name: env_traffic_area(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_traffic_area(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod2MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.traffic_area t WHERE sg.root_id = t.lod2_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.traffic_area t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.traffic_area t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.traffic_area t WHERE sg.root_id = t.lod2_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.traffic_area t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.traffic_area t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_traffic_area(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1488 (class 1255 OID 418644)
-- Name: env_transportation_complex(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_transportation_complex(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod0Network
    SELECT lod0_network AS geom FROM citydb.transportation_complex WHERE id = co_id  AND lod0_network IS NOT NULL
      UNION ALL
    -- lod1MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.transportation_complex t WHERE sg.root_id = t.lod1_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.transportation_complex t WHERE sg.root_id = t.lod2_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.transportation_complex t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.transportation_complex t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- TrafficArea
    SELECT citydb.env_traffic_area(id, set_envelope) AS geom FROM citydb.traffic_area WHERE transportation_complex_id = co_id
      UNION ALL
    -- AuxiliaryTrafficArea
    SELECT citydb.env_traffic_area(id, set_envelope) AS geom FROM citydb.traffic_area WHERE transportation_complex_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_transportation_complex(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1489 (class 1255 OID 418645)
-- Name: env_tunnel(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_tunnel(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod1Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel t WHERE sg.root_id = t.lod1_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel t WHERE sg.root_id = t.lod1_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1TerrainIntersection
    SELECT lod1_terrain_intersection AS geom FROM citydb.tunnel WHERE id = co_id  AND lod1_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod2Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel t WHERE sg.root_id = t.lod2_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel t WHERE sg.root_id = t.lod2_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2MultiCurve
    SELECT lod2_multi_curve AS geom FROM citydb.tunnel WHERE id = co_id  AND lod2_multi_curve IS NOT NULL
      UNION ALL
    -- lod2TerrainIntersection
    SELECT lod2_terrain_intersection AS geom FROM citydb.tunnel WHERE id = co_id  AND lod2_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod3Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel t WHERE sg.root_id = t.lod3_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiCurve
    SELECT lod3_multi_curve AS geom FROM citydb.tunnel WHERE id = co_id  AND lod3_multi_curve IS NOT NULL
      UNION ALL
    -- lod3TerrainIntersection
    SELECT lod3_terrain_intersection AS geom FROM citydb.tunnel WHERE id = co_id  AND lod3_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod4Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel t WHERE sg.root_id = t.lod4_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiCurve
    SELECT lod4_multi_curve AS geom FROM citydb.tunnel WHERE id = co_id  AND lod4_multi_curve IS NOT NULL
      UNION ALL
    -- lod4TerrainIntersection
    SELECT lod4_terrain_intersection AS geom FROM citydb.tunnel WHERE id = co_id  AND lod4_terrain_intersection IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- TunnelInstallation
    SELECT citydb.env_tunnel_installation(id, set_envelope) AS geom FROM citydb.tunnel_installation WHERE tunnel_id = co_id
      UNION ALL
    -- IntTunnelInstallation
    SELECT citydb.env_tunnel_installation(id, set_envelope) AS geom FROM citydb.tunnel_installation WHERE tunnel_id = co_id
      UNION ALL
    -- _BoundarySurface
    SELECT citydb.env_tunnel_thematic_surface(id, set_envelope) AS geom FROM citydb.tunnel_thematic_surface WHERE tunnel_id = co_id
      UNION ALL
    -- HollowSpace
    SELECT citydb.env_tunnel_hollow_space(id, set_envelope) AS geom FROM citydb.tunnel_hollow_space WHERE tunnel_id = co_id
      UNION ALL
    -- TunnelPart
    SELECT citydb.env_tunnel(id, set_envelope) AS geom FROM citydb.tunnel WHERE tunnel_parent_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_tunnel(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1490 (class 1255 OID 418646)
-- Name: env_tunnel_furniture(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_tunnel_furniture(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_furniture t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.tunnel_furniture WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.tunnel_furniture WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_tunnel_furniture(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1491 (class 1255 OID 418647)
-- Name: env_tunnel_hollow_space(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_tunnel_hollow_space(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod4Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_hollow_space t WHERE sg.root_id = t.lod4_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_hollow_space t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _BoundarySurface
    SELECT citydb.env_tunnel_thematic_surface(id, set_envelope) AS geom FROM citydb.tunnel_thematic_surface WHERE tunnel_hollow_space_id = co_id
      UNION ALL
    -- TunnelFurniture
    SELECT citydb.env_tunnel_furniture(id, set_envelope) AS geom FROM citydb.tunnel_furniture WHERE tunnel_hollow_space_id = co_id
      UNION ALL
    -- IntTunnelInstallation
    SELECT citydb.env_tunnel_installation(id, set_envelope) AS geom FROM citydb.tunnel_installation WHERE tunnel_hollow_space_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_tunnel_hollow_space(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1492 (class 1255 OID 418648)
-- Name: env_tunnel_installation(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_tunnel_installation(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod2Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_installation t WHERE sg.root_id = t.lod2_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2Geometry
    SELECT lod2_other_geom AS geom FROM citydb.tunnel_installation WHERE id = co_id  AND lod2_other_geom IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_installation t WHERE sg.root_id = t.lod3_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT lod3_other_geom AS geom FROM citydb.tunnel_installation WHERE id = co_id  AND lod3_other_geom IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_installation t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.tunnel_installation WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod2ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod2_implicit_rep_id, lod2_implicit_ref_point, lod2_implicit_transformation) AS geom FROM citydb.tunnel_installation WHERE id = co_id AND lod2_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod3ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod3_implicit_rep_id, lod3_implicit_ref_point, lod3_implicit_transformation) AS geom FROM citydb.tunnel_installation WHERE id = co_id AND lod3_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.tunnel_installation WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_installation t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.tunnel_installation WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.tunnel_installation WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _BoundarySurface
    SELECT citydb.env_tunnel_thematic_surface(id, set_envelope) AS geom FROM citydb.tunnel_thematic_surface WHERE tunnel_installation_id = co_id
      UNION ALL
    -- _BoundarySurface
    SELECT citydb.env_tunnel_thematic_surface(id, set_envelope) AS geom FROM citydb.tunnel_thematic_surface WHERE tunnel_installation_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_tunnel_installation(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1493 (class 1255 OID 418649)
-- Name: env_tunnel_opening(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_tunnel_opening(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_opening t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_opening t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod3_implicit_rep_id, lod3_implicit_ref_point, lod3_implicit_transformation) AS geom FROM citydb.tunnel_opening WHERE id = co_id AND lod3_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.tunnel_opening WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_tunnel_opening(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1494 (class 1255 OID 418650)
-- Name: env_tunnel_thematic_surface(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_tunnel_thematic_surface(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod2MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_thematic_surface t WHERE sg.root_id = t.lod2_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_thematic_surface t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_thematic_surface t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _Opening
    SELECT citydb.env_tunnel_opening(c.id, set_envelope) AS geom FROM citydb.tunnel_opening c, citydb.tunnel_open_to_them_srf p2c WHERE c.id = tunnel_opening_id AND p2c.tunnel_thematic_surface_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_tunnel_thematic_surface(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1495 (class 1255 OID 418651)
-- Name: env_waterbody(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_waterbody(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod0MultiCurve
    SELECT lod0_multi_curve AS geom FROM citydb.waterbody WHERE id = co_id  AND lod0_multi_curve IS NOT NULL
      UNION ALL
    -- lod0MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.waterbody t WHERE sg.root_id = t.lod0_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1MultiCurve
    SELECT lod1_multi_curve AS geom FROM citydb.waterbody WHERE id = co_id  AND lod1_multi_curve IS NOT NULL
      UNION ALL
    -- lod1MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.waterbody t WHERE sg.root_id = t.lod1_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.waterbody t WHERE sg.root_id = t.lod1_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.waterbody t WHERE sg.root_id = t.lod2_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.waterbody t WHERE sg.root_id = t.lod3_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.waterbody t WHERE sg.root_id = t.lod4_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _WaterBoundarySurface
    SELECT citydb.env_waterboundary_surface(c.id, set_envelope) AS geom FROM citydb.waterboundary_surface c, citydb.waterbod_to_waterbnd_srf p2c WHERE c.id = waterboundary_surface_id AND p2c.waterbody_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_waterbody(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1496 (class 1255 OID 418652)
-- Name: env_waterboundary_surface(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.env_waterboundary_surface(co_id integer, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod2Surface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.waterboundary_surface t WHERE sg.root_id = t.lod2_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3Surface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.waterboundary_surface t WHERE sg.root_id = t.lod3_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Surface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.waterboundary_surface t WHERE sg.root_id = t.lod4_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;


ALTER FUNCTION citydb.env_waterboundary_surface(co_id integer, set_envelope integer, caller integer) OWNER TO postgres;

--
-- TOC entry 1497 (class 1255 OID 418653)
-- Name: get_envelope_cityobjects(integer, integer, integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.get_envelope_cityobjects(objclass_id integer DEFAULT 0, set_envelope integer DEFAULT 0, only_if_null integer DEFAULT 1) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  bbox GEOMETRY;
  filter TEXT;
BEGIN
  IF only_if_null <> 0 THEN
    filter := ' WHERE envelope IS NULL';
  END IF;

  IF objclass_id <> 0 THEN
    IF filter IS NULL THEN
      filter := ' WHERE ';
    ELSE
      filter := filter || ' AND ';
    END IF;
    filter := filter || 'objectclass_id = ' || objclass_id::TEXT;
  END IF;

  IF filter IS NULL THEN
    filter := '';
  END IF;

  EXECUTE 'SELECT citydb.box2envelope(ST_3DExtent(geom)) FROM (
    SELECT citydb.env_cityobject(id, $1) AS geom
      FROM citydb.cityobject' || filter || ')g' INTO bbox USING set_envelope; 

  RETURN bbox;
END;
$_$;


ALTER FUNCTION citydb.get_envelope_cityobjects(objclass_id integer, set_envelope integer, only_if_null integer) OWNER TO postgres;

--
-- TOC entry 1498 (class 1255 OID 418654)
-- Name: get_envelope_implicit_geometry(integer, public.geometry, character varying); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.get_envelope_implicit_geometry(implicit_rep_id integer, ref_pt public.geometry, transform4x4 character varying) RETURNS public.geometry
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  envelope GEOMETRY;
  params DOUBLE PRECISION[ ] := '{}';
BEGIN
  -- calculate bounding box for implicit geometry

  SELECT box2envelope(ST_3DExtent(geom)) INTO envelope FROM (
    -- relative other geometry

    SELECT relative_other_geom AS geom 
      FROM citydb.implicit_geometry
        WHERE id = implicit_rep_id
          AND relative_other_geom IS NOT NULL
    UNION ALL
    -- relative brep geometry
    SELECT sg.implicit_geometry AS geom
      FROM citydb.surface_geometry sg, citydb.implicit_geometry ig
        WHERE sg.root_id = ig.relative_brep_id 
          AND ig.id = implicit_rep_id 
          AND sg.implicit_geometry IS NOT NULL
  ) g;

  IF transform4x4 IS NOT NULL THEN
    -- -- extract parameters of transformation matrix
    params := string_to_array(transform4x4, ' ')::float8[];

    IF array_length(params, 1) < 12 THEN
      RAISE EXCEPTION 'Malformed transformation matrix: %', transform4x4 USING HINT = '16 values are required';
    END IF; 
  ELSE
    params := '{
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1}';
  END IF;

  IF ref_pt IS NOT NULL THEN
    params[4] := params[4] + ST_X(ref_pt);
    params[8] := params[8] + ST_Y(ref_pt);
    params[12] := params[12] + ST_Z(ref_pt);
  END IF;

  IF envelope IS NOT NULL THEN
    -- perform affine transformation against given transformation matrix
    envelope := ST_Affine(envelope,
      params[1], params[2], params[3],
      params[5], params[6], params[7],
      params[9], params[10], params[11],
      params[4], params[8], params[12]);
  END IF;

  RETURN envelope;
END;
$$;


ALTER FUNCTION citydb.get_envelope_implicit_geometry(implicit_rep_id integer, ref_pt public.geometry, transform4x4 character varying) OWNER TO postgres;

--
-- TOC entry 1452 (class 1255 OID 418607)
-- Name: objectclass_id_to_table_name(integer); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.objectclass_id_to_table_name(class_id integer) RETURNS text
    LANGUAGE sql STABLE STRICT
    AS $_$
SELECT
  tablename
FROM
  objectclass
WHERE
  id = $1;
$_$;


ALTER FUNCTION citydb.objectclass_id_to_table_name(class_id integer) OWNER TO postgres;

--
-- TOC entry 1453 (class 1255 OID 418608)
-- Name: table_name_to_objectclass_ids(text); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.table_name_to_objectclass_ids(table_name text) RETURNS integer[]
    LANGUAGE sql STABLE STRICT
    AS $_$
WITH RECURSIVE objectclass_tree (id, superclass_id) AS (
  SELECT
    id,
    superclass_id
  FROM
    objectclass
  WHERE
    tablename = lower($1)
  UNION ALL
    SELECT
      o.id,
      o.superclass_id
    FROM
      objectclass o,
      objectclass_tree t
    WHERE
      o.superclass_id = t.id
)
SELECT
  array_agg(DISTINCT id ORDER BY id)
FROM
  objectclass_tree;
$_$;


ALTER FUNCTION citydb.table_name_to_objectclass_ids(table_name text) OWNER TO postgres;

--
-- TOC entry 1499 (class 1255 OID 418655)
-- Name: update_bounds(public.geometry, public.geometry); Type: FUNCTION; Schema: citydb; Owner: postgres
--

CREATE FUNCTION citydb.update_bounds(old_box public.geometry, new_box public.geometry) RETURNS public.geometry
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  updated_box GEOMETRY;
BEGIN
  IF old_box IS NULL AND new_box IS NULL THEN
    RETURN NULL;
  ELSE
    IF old_box IS NULL THEN
      RETURN new_box;
    END IF;

    IF new_box IS NULL THEN
      RETURN old_box;
    END IF;

    updated_box := citydb.box2envelope(ST_3DExtent(ST_Collect(old_box, new_box)));
  END IF;

  RETURN updated_box;
END;
$$;


ALTER FUNCTION citydb.update_bounds(old_box public.geometry, new_box public.geometry) OWNER TO postgres;

--
-- TOC entry 1629 (class 1255 OID 418790)
-- Name: change_column_srid(text, text, integer, integer, integer, text, text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.change_column_srid(table_name text, column_name text, dim integer, schema_srid integer, transform integer DEFAULT 0, geom_type text DEFAULT 'GEOMETRY'::text, schema_name text DEFAULT 'citydb'::text) RETURNS SETOF void
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  idx_name TEXT;
  opclass_param TEXT;
  geometry_type TEXT;
BEGIN
  -- check if a spatial index is defined for the column
  SELECT 
    pgc_i.relname,
    pgoc.opcname
  INTO
    idx_name,
    opclass_param
  FROM pg_class pgc_t
  JOIN pg_index pgi ON pgi.indrelid = pgc_t.oid  
  JOIN pg_class pgc_i ON pgc_i.oid = pgi.indexrelid
  JOIN pg_opclass pgoc ON pgoc.oid = pgi.indclass[0]
  JOIN pg_am pgam ON pgam.oid = pgc_i.relam
  JOIN pg_attribute pga ON pga.attrelid = pgc_i.oid
  JOIN pg_namespace pgns ON pgns.oid = pgc_i.relnamespace
  WHERE pgns.nspname = lower($7)
    AND pgc_t.relname = lower($1)
    AND pga.attname = lower($2)
    AND pgam.amname = 'gist';

  IF idx_name IS NOT NULL THEN
    -- drop spatial index if exists
    EXECUTE format('DROP INDEX %I.%I', $7, idx_name);
  END IF;

  IF transform <> 0 THEN
    -- construct correct geometry type
    IF dim = 3 AND substr($6,length($6),length($6)) <> 'M' THEN
      geometry_type := $6 || 'Z';
    ELSIF dim = 4 THEN
      geometry_type := $6 || 'ZM';
    ELSE
      geometry_type := $6;
    END IF;

    -- coordinates of existent geometries will be transformed
    EXECUTE format('ALTER TABLE %I.%I ALTER COLUMN %I TYPE geometry(%I,%L) USING ST_Transform(%I,%L::int)',
                     $7, $1, $2, geometry_type, $4, $2, $4);
  ELSE
    -- only metadata of geometry columns is updated, coordinates keep unchanged
    PERFORM UpdateGeometrySRID($7, $1, $2, $4);
  END IF;

  IF idx_name IS NOT NULL THEN
    -- recreate spatial index again
    EXECUTE format('CREATE INDEX %I ON %I.%I USING GIST (%I %I)', idx_name, $7, $1, $2, opclass_param);
  END IF;
END;
$_$;


ALTER FUNCTION citydb_pkg.change_column_srid(table_name text, column_name text, dim integer, schema_srid integer, transform integer, geom_type text, schema_name text) OWNER TO postgres;

--
-- TOC entry 1630 (class 1255 OID 418791)
-- Name: change_schema_srid(integer, text, integer, text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.change_schema_srid(schema_srid integer, schema_gml_srs_name text, transform integer DEFAULT 0, schema_name text DEFAULT 'citydb'::text) RETURNS SETOF void
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  current_srid INTEGER;
  update_string TEXT := format('UPDATE %I.database_srs SET gml_srs_name = %L', $4, $2);
BEGIN
  -- check if user selected valid srid
  -- will raise an exception if not
  PERFORM citydb_pkg.check_srid($1);

  -- get current srid for given schema
  EXECUTE format('SELECT srid FROM %I.database_srs', $4) INTO current_srid;

  IF current_srid IS NOT NULL THEN
    -- update entry in database_srs table first
    IF current_srid = schema_srid THEN
      EXECUTE update_string;
    ELSE
      EXECUTE update_string || ', srid = $1' USING $1;

      -- change srid of spatial columns in given schema with current srid
      PERFORM citydb_pkg.change_column_srid(f_table_name, f_geometry_column, coord_dimension, $1, $3, type, f_table_schema) 
        FROM geometry_columns
        WHERE f_table_schema = lower($4)
          AND srid = current_srid
          AND f_geometry_column <> 'implicit_geometry'
          AND f_geometry_column <> 'relative_other_geom'
          AND f_geometry_column <> 'texture_coordinates';
    END IF;
  END IF;
END;
$_$;


ALTER FUNCTION citydb_pkg.change_schema_srid(schema_srid integer, schema_gml_srs_name text, transform integer, schema_name text) OWNER TO postgres;

--
-- TOC entry 1627 (class 1255 OID 418788)
-- Name: check_srid(integer); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.check_srid(srsno integer DEFAULT 0) RETURNS text
    LANGUAGE plpgsql STABLE STRICT
    AS $_$
DECLARE
  schema_srid INTEGER;
BEGIN
  SELECT srid INTO schema_srid FROM spatial_ref_sys WHERE srid = $1;

  IF schema_srid IS NULL THEN
    RAISE EXCEPTION 'Table spatial_ref_sys does not contain the SRID %. Insert commands for missing SRIDs can be found at spatialreference.org', srsno;
    RETURN 'SRID not ok';
  END IF;

  RETURN 'SRID ok';
END;
$_$;


ALTER FUNCTION citydb_pkg.check_srid(srsno integer) OWNER TO postgres;

--
-- TOC entry 1596 (class 1255 OID 418757)
-- Name: citydb_version(); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.citydb_version(OUT version text, OUT major_version integer, OUT minor_version integer, OUT minor_revision integer) RETURNS record
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT 
  '4.1.0'::text AS version,
  4 AS major_version, 
  1 AS minor_version,
  0 AS minor_revision;
$$;


ALTER FUNCTION citydb_pkg.citydb_version(OUT version text, OUT major_version integer, OUT minor_version integer, OUT minor_revision integer) OWNER TO postgres;

--
-- TOC entry 1611 (class 1255 OID 418772)
-- Name: construct_normal(text, text, text, integer); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.construct_normal(ind_name text, tab_name text, att_name text, crs integer DEFAULT 0) RETURNS citydb_pkg.index_obj
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
SELECT ($1, $2, $3, 0, $4, 0)::citydb_pkg.INDEX_OBJ;
$_$;


ALTER FUNCTION citydb_pkg.construct_normal(ind_name text, tab_name text, att_name text, crs integer) OWNER TO postgres;

--
-- TOC entry 1610 (class 1255 OID 418771)
-- Name: construct_spatial_2d(text, text, text, integer); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.construct_spatial_2d(ind_name text, tab_name text, att_name text, crs integer DEFAULT 0) RETURNS citydb_pkg.index_obj
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
SELECT ($1, $2, $3, 1, $4, 0)::citydb_pkg.INDEX_OBJ;
$_$;


ALTER FUNCTION citydb_pkg.construct_spatial_2d(ind_name text, tab_name text, att_name text, crs integer) OWNER TO postgres;

--
-- TOC entry 1609 (class 1255 OID 418770)
-- Name: construct_spatial_3d(text, text, text, integer); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.construct_spatial_3d(ind_name text, tab_name text, att_name text, crs integer DEFAULT 0) RETURNS citydb_pkg.index_obj
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
SELECT ($1, $2, $3, 1, $4, 1)::citydb_pkg.INDEX_OBJ;
$_$;


ALTER FUNCTION citydb_pkg.construct_spatial_3d(ind_name text, tab_name text, att_name text, crs integer) OWNER TO postgres;

--
-- TOC entry 1614 (class 1255 OID 418775)
-- Name: create_index(citydb_pkg.index_obj, text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.create_index(idx citydb_pkg.index_obj, schema_name text DEFAULT 'citydb'::text) RETURNS text
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  create_ddl TEXT;
  SPATIAL CONSTANT NUMERIC(1) := 1;
BEGIN
  IF citydb_pkg.index_status($1, $2) <> 'VALID' THEN
    PERFORM citydb_pkg.drop_index($1, $2);

    BEGIN
      IF ($1).type = SPATIAL THEN
        IF ($1).is_3d = 1 THEN
          EXECUTE format(
            'CREATE INDEX %I ON %I.%I USING GIST (%I gist_geometry_ops_nd)',
            ($1).index_name, $2, ($1).table_name, ($1).attribute_name);
        ELSE
          EXECUTE format(
            'CREATE INDEX %I ON %I.%I USING GIST (%I gist_geometry_ops_2d)',
            ($1).index_name, $2, ($1).table_name, ($1).attribute_name);
        END IF;
      ELSE
        EXECUTE format(
          'CREATE INDEX %I ON %I.%I USING BTREE ('|| idx.attribute_name || ')',
          idx.index_name, schema_name, idx.table_name);
      END IF;

      EXCEPTION
        WHEN OTHERS THEN
          RETURN SQLSTATE || ' - ' || SQLERRM;
    END;
  END IF;

  RETURN '0';
END;
$_$;


ALTER FUNCTION citydb_pkg.create_index(idx citydb_pkg.index_obj, schema_name text) OWNER TO postgres;

--
-- TOC entry 1616 (class 1255 OID 418777)
-- Name: create_indexes(integer, text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.create_indexes(idx_type integer, schema_name text DEFAULT 'citydb'::text) RETURNS text[]
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  idx_log text[] := '{}';
  sql_error_msg TEXT;
  rec RECORD;
BEGIN
  FOR rec IN EXECUTE format('
    SELECT * FROM %I.index_table WHERE (obj).type = %L', $2, $1)
  LOOP
    sql_error_msg := citydb_pkg.create_index(rec.obj, $2);
    idx_log := array_append(
      idx_log,
      citydb_pkg.index_status(rec.obj, $2)
      || ':' || (rec.obj).index_name
      || ':' || $2
      || ':' || (rec.obj).table_name
      || ':' || (rec.obj).attribute_name
      || ':' || sql_error_msg
    );
  END LOOP;

  RETURN idx_log;
END;
$_$;


ALTER FUNCTION citydb_pkg.create_indexes(idx_type integer, schema_name text) OWNER TO postgres;

--
-- TOC entry 1622 (class 1255 OID 418783)
-- Name: create_normal_indexes(text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.create_normal_indexes(schema_name text DEFAULT 'citydb'::text) RETURNS text[]
    LANGUAGE sql STRICT
    AS $_$
SELECT citydb_pkg.create_indexes(0, $1);
$_$;


ALTER FUNCTION citydb_pkg.create_normal_indexes(schema_name text) OWNER TO postgres;

--
-- TOC entry 1620 (class 1255 OID 418781)
-- Name: create_spatial_indexes(text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.create_spatial_indexes(schema_name text DEFAULT 'citydb'::text) RETURNS text[]
    LANGUAGE sql STRICT
    AS $_$
SELECT citydb_pkg.create_indexes(1, $1);
$_$;


ALTER FUNCTION citydb_pkg.create_spatial_indexes(schema_name text) OWNER TO postgres;

--
-- TOC entry 1599 (class 1255 OID 418760)
-- Name: db_info(text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.db_info(schema_name text DEFAULT 'citydb'::text, OUT schema_srid integer, OUT schema_gml_srs_name text, OUT versioning text) RETURNS record
    LANGUAGE plpgsql STABLE
    AS $_$
BEGIN
  EXECUTE format(
    'SELECT 
       srid, gml_srs_name, citydb_pkg.versioning_db($1)
     FROM
       %I.database_srs', schema_name)
    USING schema_name
    INTO schema_srid, schema_gml_srs_name, versioning;
END;
$_$;


ALTER FUNCTION citydb_pkg.db_info(schema_name text, OUT schema_srid integer, OUT schema_gml_srs_name text, OUT versioning text) OWNER TO postgres;

--
-- TOC entry 1600 (class 1255 OID 418761)
-- Name: db_metadata(text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.db_metadata(schema_name text DEFAULT 'citydb'::text, OUT schema_srid integer, OUT schema_gml_srs_name text, OUT coord_ref_sys_name text, OUT coord_ref_sys_kind text, OUT wktext text, OUT versioning text) RETURNS record
    LANGUAGE plpgsql STABLE
    AS $_$
BEGIN
  EXECUTE format(
    'SELECT 
       d.srid,
       d.gml_srs_name,
       split_part(s.srtext, ''"'', 2),
       split_part(s.srtext, ''['', 1),
       s.srtext,
       citydb_pkg.versioning_db($1) AS versioning
     FROM 
       %I.database_srs d,
       spatial_ref_sys s 
     WHERE
       d.srid = s.srid', schema_name)
    USING schema_name
    INTO schema_srid, schema_gml_srs_name, coord_ref_sys_name, coord_ref_sys_kind, wktext, versioning;
END;
$_$;


ALTER FUNCTION citydb_pkg.db_metadata(schema_name text, OUT schema_srid integer, OUT schema_gml_srs_name text, OUT coord_ref_sys_name text, OUT coord_ref_sys_kind text, OUT wktext text, OUT versioning text) OWNER TO postgres;

--
-- TOC entry 1615 (class 1255 OID 418776)
-- Name: drop_index(citydb_pkg.index_obj, text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.drop_index(idx citydb_pkg.index_obj, schema_name text DEFAULT 'citydb'::text) RETURNS text
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  index_name TEXT;
BEGIN
  IF citydb_pkg.index_status($1, $2) <> 'DROPPED' THEN
    BEGIN
      EXECUTE format(
        'DROP INDEX IF EXISTS %I.%I',
        $2, ($1).index_name);

      EXCEPTION
        WHEN OTHERS THEN
          RETURN SQLSTATE || ' - ' || SQLERRM;
    END;
  END IF;

  RETURN '0';
END;
$_$;


ALTER FUNCTION citydb_pkg.drop_index(idx citydb_pkg.index_obj, schema_name text) OWNER TO postgres;

--
-- TOC entry 1617 (class 1255 OID 418778)
-- Name: drop_indexes(integer, text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.drop_indexes(idx_type integer, schema_name text DEFAULT 'citydb'::text) RETURNS text[]
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  idx_log text[] := '{}';
  sql_error_msg TEXT;
  rec RECORD;
BEGIN
  FOR rec IN EXECUTE format('
    SELECT * FROM %I.index_table WHERE (obj).type = %L', $2, $1)
  LOOP
    sql_error_msg := citydb_pkg.drop_index(rec.obj, $2);
    idx_log := array_append(
      idx_log,
      citydb_pkg.index_status(rec.obj, $2)
      || ':' || (rec.obj).index_name
      || ':' || $2
      || ':' || (rec.obj).table_name
      || ':' || (rec.obj).attribute_name
      || ':' || sql_error_msg
    );
  END LOOP;

  RETURN idx_log;
END;
$_$;


ALTER FUNCTION citydb_pkg.drop_indexes(idx_type integer, schema_name text) OWNER TO postgres;

--
-- TOC entry 1623 (class 1255 OID 418784)
-- Name: drop_normal_indexes(text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.drop_normal_indexes(schema_name text DEFAULT 'citydb'::text) RETURNS text[]
    LANGUAGE sql STRICT
    AS $_$
SELECT citydb_pkg.drop_indexes(0, $1); 
$_$;


ALTER FUNCTION citydb_pkg.drop_normal_indexes(schema_name text) OWNER TO postgres;

--
-- TOC entry 1621 (class 1255 OID 418782)
-- Name: drop_spatial_indexes(text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.drop_spatial_indexes(schema_name text DEFAULT 'citydb'::text) RETURNS text[]
    LANGUAGE sql STRICT
    AS $_$
SELECT citydb_pkg.drop_indexes(1, $1);
$_$;


ALTER FUNCTION citydb_pkg.drop_spatial_indexes(schema_name text) OWNER TO postgres;

--
-- TOC entry 1603 (class 1255 OID 418764)
-- Name: drop_tmp_tables(text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.drop_tmp_tables(schema_name text DEFAULT 'citydb'::text) RETURNS SETOF void
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN SELECT table_name FROM information_schema.tables WHERE table_schema = $1 AND table_name LIKE 'tmp_%' LOOP
    EXECUTE format('DROP TABLE %I.%I', $1, rec.table_name); 	
  END LOOP; 
END;
$_$;


ALTER FUNCTION citydb_pkg.drop_tmp_tables(schema_name text) OWNER TO postgres;

--
-- TOC entry 1624 (class 1255 OID 418785)
-- Name: get_index(text, text, text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.get_index(idx_table_name text, idx_column_name text, schema_name text DEFAULT 'citydb'::text) RETURNS citydb_pkg.index_obj
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  index_name TEXT;
  table_name TEXT;
  attribute_name TEXT;
  type NUMERIC(1);
  srid INTEGER;
  is_3d NUMERIC(1, 0);
BEGIN
  EXECUTE format('
		SELECT
		  (obj).index_name,
		  (obj).table_name,
		  (obj).attribute_name,
		  (obj).type,
		  (obj).srid,
		  (obj).is_3d
		FROM
		  %I.index_table 
		WHERE
		  (obj).table_name = lower(''%I'')
		  AND (obj).attribute_name = lower(''%I'')', $3, $1, $2) INTO index_name, table_name, attribute_name, type, srid, is_3d;

  IF index_name IS NOT NULL THEN
    RETURN (index_name, table_name, attribute_name, type, srid, is_3d)::citydb_pkg.INDEX_OBJ;
  ELSE
    RETURN NULL;
  END IF;
END;
$_$;


ALTER FUNCTION citydb_pkg.get_index(idx_table_name text, idx_column_name text, schema_name text) OWNER TO postgres;

--
-- TOC entry 1602 (class 1255 OID 418763)
-- Name: get_seq_values(text, integer); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.get_seq_values(seq_name text, seq_count integer) RETURNS SETOF integer
    LANGUAGE sql STRICT
    AS $_$
SELECT nextval($1)::int FROM generate_series(1, $2);
$_$;


ALTER FUNCTION citydb_pkg.get_seq_values(seq_name text, seq_count integer) OWNER TO postgres;

--
-- TOC entry 1612 (class 1255 OID 418773)
-- Name: index_status(citydb_pkg.index_obj, text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.index_status(idx citydb_pkg.index_obj, schema_name text DEFAULT 'citydb'::text) RETURNS text
    LANGUAGE plpgsql STABLE STRICT
    AS $_$
DECLARE
  is_valid BOOLEAN;
  status TEXT;
BEGIN
  SELECT
    pgi.indisvalid
  INTO
    is_valid
  FROM
    pg_index pgi
  JOIN
    pg_class pgc
    ON pgc.oid = pgi.indexrelid
  JOIN
    pg_namespace pgn
    ON pgn.oid = pgc.relnamespace
  WHERE
    pgn.nspname = $2
    AND pgc.relname = ($1).index_name;

  IF is_valid is null THEN
    status := 'DROPPED';
  ELSIF is_valid = true THEN
    status := 'VALID';
  ELSE
    status := 'INVALID';
  END IF;

  RETURN status;

  EXCEPTION
    WHEN OTHERS THEN
      RETURN 'FAILED';
END;
$_$;


ALTER FUNCTION citydb_pkg.index_status(idx citydb_pkg.index_obj, schema_name text) OWNER TO postgres;

--
-- TOC entry 1613 (class 1255 OID 418774)
-- Name: index_status(text, text, text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.index_status(idx_table_name text, idx_column_name text, schema_name text DEFAULT 'citydb'::text) RETURNS text
    LANGUAGE plpgsql STABLE STRICT
    AS $_$
DECLARE
  is_valid BOOLEAN;
  status TEXT;
BEGIN
  SELECT
    pgi.indisvalid
  INTO
    is_valid
  FROM
    pg_index pgi
  JOIN
    pg_attribute pga
    ON pga.attrelid = pgi.indexrelid
  WHERE
    pgi.indrelid = (lower($3) || '.' || lower($1))::regclass::oid
    AND pga.attname = lower($2);

  IF is_valid is null THEN
    status := 'DROPPED';
  ELSIF is_valid = true THEN
    status := 'VALID';
  ELSE
    status := 'INVALID';
  END IF;

  RETURN status;

  EXCEPTION
    WHEN OTHERS THEN
      RETURN 'FAILED';
END;
$_$;


ALTER FUNCTION citydb_pkg.index_status(idx_table_name text, idx_column_name text, schema_name text) OWNER TO postgres;

--
-- TOC entry 1625 (class 1255 OID 418786)
-- Name: is_coord_ref_sys_3d(integer); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.is_coord_ref_sys_3d(schema_srid integer) RETURNS integer
    LANGUAGE sql STABLE STRICT
    AS $_$
SELECT COALESCE((
  SELECT 1 FROM spatial_ref_sys WHERE auth_srid = $1 AND srtext LIKE '%UP]%'
  ), 0);
$_$;


ALTER FUNCTION citydb_pkg.is_coord_ref_sys_3d(schema_srid integer) OWNER TO postgres;

--
-- TOC entry 1626 (class 1255 OID 418787)
-- Name: is_db_coord_ref_sys_3d(text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.is_db_coord_ref_sys_3d(schema_name text DEFAULT 'citydb'::text) RETURNS integer
    LANGUAGE plpgsql STABLE STRICT
    AS $$
DECLARE
  is_3d INTEGER := 0;
BEGIN  
  EXECUTE format(
    'SELECT citydb_pkg.is_coord_ref_sys_3d(srid) FROM %I.database_srs', schema_name
  )
  INTO is_3d;

  RETURN is_3d;
END;
$$;


ALTER FUNCTION citydb_pkg.is_db_coord_ref_sys_3d(schema_name text) OWNER TO postgres;

--
-- TOC entry 1601 (class 1255 OID 418762)
-- Name: min(numeric, numeric); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.min(a numeric, b numeric) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    AS $_$
SELECT LEAST($1,$2);
$_$;


ALTER FUNCTION citydb_pkg.min(a numeric, b numeric) OWNER TO postgres;

--
-- TOC entry 1606 (class 1255 OID 418767)
-- Name: set_enabled_fkey(oid, boolean); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.set_enabled_fkey(fkey_trigger_oid oid, enable boolean DEFAULT true) RETURNS SETOF void
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  tgstatus char(1);
BEGIN
  IF $2 THEN
    tgstatus := 'O';
  ELSE
    tgstatus := 'D';
  END IF;

  UPDATE
    pg_trigger
  SET
    tgenabled = tgstatus
  WHERE
    oid = $1;
END;
$_$;


ALTER FUNCTION citydb_pkg.set_enabled_fkey(fkey_trigger_oid oid, enable boolean) OWNER TO postgres;

--
-- TOC entry 1607 (class 1255 OID 418768)
-- Name: set_enabled_geom_fkeys(boolean, text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.set_enabled_geom_fkeys(enable boolean DEFAULT true, schema_name text DEFAULT 'citydb'::text) RETURNS SETOF void
    LANGUAGE sql STRICT
    AS $_$
SELECT
  citydb_pkg.set_enabled_fkey(
    t.oid,
    $1
  )
FROM
  pg_constraint c
JOIN
  pg_trigger t
  ON t.tgconstraint = c.oid
WHERE
  c.contype = 'f'
  AND c.confrelid = (lower($2) || '.surface_geometry')::regclass::oid
  AND c.confdeltype <> 'c'
$_$;


ALTER FUNCTION citydb_pkg.set_enabled_geom_fkeys(enable boolean, schema_name text) OWNER TO postgres;

--
-- TOC entry 1608 (class 1255 OID 418769)
-- Name: set_enabled_schema_fkeys(boolean, text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.set_enabled_schema_fkeys(enable boolean DEFAULT true, schema_name text DEFAULT 'citydb'::text) RETURNS SETOF void
    LANGUAGE sql STRICT
    AS $_$
SELECT
  citydb_pkg.set_enabled_fkey(
    t.oid,
    $1
  )
FROM
  pg_constraint c
JOIN
  pg_namespace n
  ON n.oid = c.connamespace
JOIN
  pg_trigger t
  ON t.tgconstraint = c.oid
WHERE
  c.contype = 'f'
  AND c.confdeltype <> 'c'
  AND n.nspname = $2;
$_$;


ALTER FUNCTION citydb_pkg.set_enabled_schema_fkeys(enable boolean, schema_name text) OWNER TO postgres;

--
-- TOC entry 1604 (class 1255 OID 418765)
-- Name: set_fkey_delete_rule(text, text, text, text, text, character, text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.set_fkey_delete_rule(fkey_name text, table_name text, column_name text, ref_table text, ref_column text, on_delete_param character DEFAULT 'a'::bpchar, schema_name text DEFAULT 'citydb'::text) RETURNS SETOF void
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  delete_param VARCHAR(9);
BEGIN
  CASE on_delete_param
    WHEN 'r' THEN delete_param := 'RESTRICT';
    WHEN 'c' THEN delete_param := 'CASCADE';
    WHEN 'n' THEN delete_param := 'SET NULL';
    ELSE delete_param := 'NO ACTION';
  END CASE;

  EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT %I, ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES %I.%I (%I) MATCH FULL
                    ON UPDATE CASCADE ON DELETE ' || delete_param, $7, $2, $1, $1, $3, $7, $4, $5);

  EXCEPTION
    WHEN OTHERS THEN
      RAISE NOTICE 'Error on constraint %: %', fkey_name, SQLERRM;
END;
$_$;


ALTER FUNCTION citydb_pkg.set_fkey_delete_rule(fkey_name text, table_name text, column_name text, ref_table text, ref_column text, on_delete_param character, schema_name text) OWNER TO postgres;

--
-- TOC entry 1605 (class 1255 OID 418766)
-- Name: set_schema_fkeys_delete_rule(character, text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.set_schema_fkeys_delete_rule(on_delete_param character DEFAULT 'a'::bpchar, schema_name text DEFAULT 'citydb'::text) RETURNS SETOF void
    LANGUAGE sql STRICT
    AS $_$
SELECT
  citydb_pkg.set_fkey_delete_rule(
    c.conname,
    c.conrelid::regclass::text,
    a.attname,
    t.relname,
    a_ref.attname,
    $1,
    n.nspname
  )
FROM pg_constraint c
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
JOIN pg_attribute a_ref ON a_ref.attrelid = c.confrelid AND a_ref.attnum = ANY (c.confkey)
JOIN pg_class t ON t.oid = a_ref.attrelid
JOIN pg_namespace n ON n.oid = c.connamespace
  WHERE n.nspname = $2
    AND c.contype = 'f';
$_$;


ALTER FUNCTION citydb_pkg.set_schema_fkeys_delete_rule(on_delete_param character, schema_name text) OWNER TO postgres;

--
-- TOC entry 1619 (class 1255 OID 418780)
-- Name: status_normal_indexes(text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.status_normal_indexes(schema_name text DEFAULT 'citydb'::text) RETURNS text[]
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  idx_log text[] := '{}';
BEGIN
	EXECUTE format('
		SELECT
		  array_agg(
		    concat(citydb_pkg.index_status(obj,' || '''%I''' || '),' || ''':''' || ',' ||
		    '(obj).index_name,' || ''':''' || ',' ||
		    '''%I'',' || ''':''' || ',' ||		    
		    '(obj).table_name,' || ''':''' || ',' ||
		    '(obj).attribute_name
		  )) AS log
		FROM
		  %I.index_table
		WHERE
		  (obj).type = 0',$1, $1, $1) INTO idx_log;
		  
	RETURN idx_log;
END;
$_$;


ALTER FUNCTION citydb_pkg.status_normal_indexes(schema_name text) OWNER TO postgres;

--
-- TOC entry 1618 (class 1255 OID 418779)
-- Name: status_spatial_indexes(text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.status_spatial_indexes(schema_name text DEFAULT 'citydb'::text) RETURNS text[]
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  idx_log text[] := '{}';
BEGIN
	EXECUTE format('
		SELECT
		  array_agg(
		    concat(citydb_pkg.index_status(obj,' || '''%I''' || '),' || ''':''' || ',' ||
		    '(obj).index_name,' || ''':''' || ',' ||
		    '''%I'',' || ''':''' || ',' ||		    
		    '(obj).table_name,' || ''':''' || ',' ||
		    '(obj).attribute_name
		  )) AS log
		FROM
		  %I.index_table
		WHERE
		  (obj).type = 1',$1, $1, $1) INTO idx_log;
	  
  RETURN idx_log;
END;
$_$;


ALTER FUNCTION citydb_pkg.status_spatial_indexes(schema_name text) OWNER TO postgres;

--
-- TOC entry 1631 (class 1255 OID 418792)
-- Name: table_content(text, text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.table_content(table_name text, schema_name text DEFAULT 'citydb'::text) RETURNS integer
    LANGUAGE plpgsql STABLE STRICT
    AS $_$
DECLARE
  cnt INTEGER;  
BEGIN
  EXECUTE format('SELECT count(*) FROM %I.%I', $2, $1) INTO cnt;
  RETURN cnt;
END;
$_$;


ALTER FUNCTION citydb_pkg.table_content(table_name text, schema_name text) OWNER TO postgres;

--
-- TOC entry 1632 (class 1255 OID 418793)
-- Name: table_contents(text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.table_contents(schema_name text DEFAULT 'citydb'::text) RETURNS text[]
    LANGUAGE sql STABLE STRICT
    AS $_$
SELECT 
  array_cat(
    ARRAY[
      'Database Report on 3D City Model - Report date: ' || to_char(now()::timestamp, 'DD.MM.YYYY HH24:MI:SS'),
      '==================================================================='
    ],
    array_agg(t.tab)
  ) AS report
FROM (
  SELECT
    '#' || upper(table_name) || (
    CASE WHEN length(table_name) < 7 THEN E'\t\t\t\t'
      WHEN length(table_name) > 6 AND length(table_name) < 15 THEN E'\t\t\t'
      WHEN length(table_name) > 14 AND length(table_name) < 23 THEN E'\t\t'
      WHEN length(table_name) > 22 THEN E'\t'
    END
    ) || citydb_pkg.table_content(table_name, $1) AS tab 
  FROM
    information_schema.tables
  WHERE 
    table_schema = $1
    AND table_name != 'database_srs' 
    AND table_name != 'objectclass'
    AND table_name != 'ade'
    AND table_name != 'schema'
    AND table_name != 'schema_to_objectclass' 
    AND table_name != 'schema_referencing'
    AND table_name != 'aggregation_info'
    AND table_name != 'index_table'
    AND table_name NOT LIKE 'tmp_%'
  ORDER BY
    table_name ASC
) t
$_$;


ALTER FUNCTION citydb_pkg.table_contents(schema_name text) OWNER TO postgres;

--
-- TOC entry 1628 (class 1255 OID 418789)
-- Name: transform_or_null(public.geometry, integer); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.transform_or_null(geom public.geometry, srid integer) RETURNS public.geometry
    LANGUAGE plpgsql STABLE
    AS $_$
BEGIN
  IF geom IS NOT NULL THEN
    RETURN ST_Transform($1, $2);
  ELSE
    RETURN NULL;
  END IF;
END;
$_$;


ALTER FUNCTION citydb_pkg.transform_or_null(geom public.geometry, srid integer) OWNER TO postgres;

--
-- TOC entry 1598 (class 1255 OID 418759)
-- Name: versioning_db(text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.versioning_db(schema_name text DEFAULT 'citydb'::text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT 'OFF'::text;
$$;


ALTER FUNCTION citydb_pkg.versioning_db(schema_name text) OWNER TO postgres;

--
-- TOC entry 1597 (class 1255 OID 418758)
-- Name: versioning_table(text, text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.versioning_table(table_name text, schema_name text DEFAULT 'citydb'::text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT 'OFF'::text;
$$;


ALTER FUNCTION citydb_pkg.versioning_table(table_name text, schema_name text) OWNER TO postgres;

--
-- TOC entry 229 (class 1259 OID 416308)
-- Name: address_seq; Type: SEQUENCE; Schema: citydb; Owner: postgres
--

CREATE SEQUENCE citydb.address_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE citydb.address_seq OWNER TO postgres;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- TOC entry 279 (class 1259 OID 416651)
-- Name: address; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.address (
    id integer DEFAULT nextval('citydb.address_seq'::regclass) NOT NULL,
    gmlid character varying(256),
    gmlid_codespace character varying(1000),
    street character varying(1000),
    house_number character varying(256),
    po_box character varying(256),
    zip_code character varying(256),
    city character varying(256),
    state character varying(256),
    country character varying(256),
    multi_point public.geometry(MultiPointZ,3946),
    xal_source text
);


ALTER TABLE citydb.address OWNER TO postgres;

--
-- TOC entry 273 (class 1259 OID 416608)
-- Name: address_to_bridge; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.address_to_bridge (
    bridge_id integer NOT NULL,
    address_id integer NOT NULL
);


ALTER TABLE citydb.address_to_bridge OWNER TO postgres;

--
-- TOC entry 230 (class 1259 OID 416310)
-- Name: address_to_building; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.address_to_building (
    building_id integer NOT NULL,
    address_id integer NOT NULL
);


ALTER TABLE citydb.address_to_building OWNER TO postgres;

--
-- TOC entry 287 (class 1259 OID 416716)
-- Name: ade_seq; Type: SEQUENCE; Schema: citydb; Owner: postgres
--

CREATE SEQUENCE citydb.ade_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE citydb.ade_seq OWNER TO postgres;

--
-- TOC entry 291 (class 1259 OID 417116)
-- Name: ade; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.ade (
    id integer DEFAULT nextval('citydb.ade_seq'::regclass) NOT NULL,
    adeid character varying(256) NOT NULL,
    name character varying(1000) NOT NULL,
    description character varying(4000),
    version character varying(50),
    db_prefix character varying(10) NOT NULL,
    xml_schemamapping_file text,
    drop_db_script text,
    creation_date timestamp with time zone,
    creation_person character varying(256)
);


ALTER TABLE citydb.ade OWNER TO postgres;

--
-- TOC entry 292 (class 1259 OID 417126)
-- Name: aggregation_info; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.aggregation_info (
    child_id integer NOT NULL,
    parent_id integer NOT NULL,
    join_table_or_column_name character varying(30) NOT NULL,
    min_occurs integer,
    max_occurs integer,
    is_composite numeric
);


ALTER TABLE citydb.aggregation_info OWNER TO postgres;

--
-- TOC entry 241 (class 1259 OID 416377)
-- Name: appear_to_surface_data; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.appear_to_surface_data (
    surface_data_id integer NOT NULL,
    appearance_id integer NOT NULL
);


ALTER TABLE citydb.appear_to_surface_data OWNER TO postgres;

--
-- TOC entry 238 (class 1259 OID 416365)
-- Name: appearance_seq; Type: SEQUENCE; Schema: citydb; Owner: postgres
--

CREATE SEQUENCE citydb.appearance_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE citydb.appearance_seq OWNER TO postgres;

--
-- TOC entry 276 (class 1259 OID 416624)
-- Name: appearance; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.appearance (
    id integer DEFAULT nextval('citydb.appearance_seq'::regclass) NOT NULL,
    gmlid character varying(256),
    gmlid_codespace character varying(1000),
    name character varying(1000),
    name_codespace character varying(4000),
    description character varying(4000),
    theme character varying(256),
    citymodel_id integer,
    cityobject_id integer
);


ALTER TABLE citydb.appearance OWNER TO postgres;

--
-- TOC entry 242 (class 1259 OID 416382)
-- Name: breakline_relief; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.breakline_relief (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    ridge_or_valley_lines public.geometry(MultiLineStringZ,3946),
    break_lines public.geometry(MultiLineStringZ,3946)
);


ALTER TABLE citydb.breakline_relief OWNER TO postgres;

--
-- TOC entry 265 (class 1259 OID 416550)
-- Name: bridge; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.bridge (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    bridge_parent_id integer,
    bridge_root_id integer,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    year_of_construction date,
    year_of_demolition date,
    is_movable numeric,
    lod1_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod2_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod3_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod4_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod2_multi_curve public.geometry(MultiLineStringZ,3946),
    lod3_multi_curve public.geometry(MultiLineStringZ,3946),
    lod4_multi_curve public.geometry(MultiLineStringZ,3946),
    lod1_multi_surface_id integer,
    lod2_multi_surface_id integer,
    lod3_multi_surface_id integer,
    lod4_multi_surface_id integer,
    lod1_solid_id integer,
    lod2_solid_id integer,
    lod3_solid_id integer,
    lod4_solid_id integer
);


ALTER TABLE citydb.bridge OWNER TO postgres;

--
-- TOC entry 272 (class 1259 OID 416600)
-- Name: bridge_constr_element; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.bridge_constr_element (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    bridge_id integer,
    lod1_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod2_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod3_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod4_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod1_brep_id integer,
    lod2_brep_id integer,
    lod3_brep_id integer,
    lod4_brep_id integer,
    lod1_other_geom public.geometry(GeometryZ,3946),
    lod2_other_geom public.geometry(GeometryZ,3946),
    lod3_other_geom public.geometry(GeometryZ,3946),
    lod4_other_geom public.geometry(GeometryZ,3946),
    lod1_implicit_rep_id integer,
    lod2_implicit_rep_id integer,
    lod3_implicit_rep_id integer,
    lod4_implicit_rep_id integer,
    lod1_implicit_ref_point public.geometry(PointZ,3946),
    lod2_implicit_ref_point public.geometry(PointZ,3946),
    lod3_implicit_ref_point public.geometry(PointZ,3946),
    lod4_implicit_ref_point public.geometry(PointZ,3946),
    lod1_implicit_transformation character varying(1000),
    lod2_implicit_transformation character varying(1000),
    lod3_implicit_transformation character varying(1000),
    lod4_implicit_transformation character varying(1000)
);


ALTER TABLE citydb.bridge_constr_element OWNER TO postgres;

--
-- TOC entry 266 (class 1259 OID 416558)
-- Name: bridge_furniture; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.bridge_furniture (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    bridge_room_id integer,
    lod4_brep_id integer,
    lod4_other_geom public.geometry(GeometryZ,3946),
    lod4_implicit_rep_id integer,
    lod4_implicit_ref_point public.geometry(PointZ,3946),
    lod4_implicit_transformation character varying(1000)
);


ALTER TABLE citydb.bridge_furniture OWNER TO postgres;

--
-- TOC entry 267 (class 1259 OID 416566)
-- Name: bridge_installation; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.bridge_installation (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    bridge_id integer,
    bridge_room_id integer,
    lod2_brep_id integer,
    lod3_brep_id integer,
    lod4_brep_id integer,
    lod2_other_geom public.geometry(GeometryZ,3946),
    lod3_other_geom public.geometry(GeometryZ,3946),
    lod4_other_geom public.geometry(GeometryZ,3946),
    lod2_implicit_rep_id integer,
    lod3_implicit_rep_id integer,
    lod4_implicit_rep_id integer,
    lod2_implicit_ref_point public.geometry(PointZ,3946),
    lod3_implicit_ref_point public.geometry(PointZ,3946),
    lod4_implicit_ref_point public.geometry(PointZ,3946),
    lod2_implicit_transformation character varying(1000),
    lod3_implicit_transformation character varying(1000),
    lod4_implicit_transformation character varying(1000)
);


ALTER TABLE citydb.bridge_installation OWNER TO postgres;

--
-- TOC entry 269 (class 1259 OID 416582)
-- Name: bridge_open_to_them_srf; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.bridge_open_to_them_srf (
    bridge_opening_id integer NOT NULL,
    bridge_thematic_surface_id integer NOT NULL
);


ALTER TABLE citydb.bridge_open_to_them_srf OWNER TO postgres;

--
-- TOC entry 268 (class 1259 OID 416574)
-- Name: bridge_opening; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.bridge_opening (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    address_id integer,
    lod3_multi_surface_id integer,
    lod4_multi_surface_id integer,
    lod3_implicit_rep_id integer,
    lod4_implicit_rep_id integer,
    lod3_implicit_ref_point public.geometry(PointZ,3946),
    lod4_implicit_ref_point public.geometry(PointZ,3946),
    lod3_implicit_transformation character varying(1000),
    lod4_implicit_transformation character varying(1000)
);


ALTER TABLE citydb.bridge_opening OWNER TO postgres;

--
-- TOC entry 270 (class 1259 OID 416587)
-- Name: bridge_room; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.bridge_room (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    bridge_id integer,
    lod4_multi_surface_id integer,
    lod4_solid_id integer
);


ALTER TABLE citydb.bridge_room OWNER TO postgres;

--
-- TOC entry 271 (class 1259 OID 416595)
-- Name: bridge_thematic_surface; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.bridge_thematic_surface (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    bridge_id integer,
    bridge_room_id integer,
    bridge_installation_id integer,
    bridge_constr_element_id integer,
    lod2_multi_surface_id integer,
    lod3_multi_surface_id integer,
    lod4_multi_surface_id integer
);


ALTER TABLE citydb.bridge_thematic_surface OWNER TO postgres;

--
-- TOC entry 231 (class 1259 OID 416315)
-- Name: building; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.building (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    building_parent_id integer,
    building_root_id integer,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    year_of_construction date,
    year_of_demolition date,
    roof_type character varying(256),
    roof_type_codespace character varying(4000),
    measured_height double precision,
    measured_height_unit character varying(4000),
    storeys_above_ground numeric(8,0),
    storeys_below_ground numeric(8,0),
    storey_heights_above_ground character varying(4000),
    storey_heights_ag_unit character varying(4000),
    storey_heights_below_ground character varying(4000),
    storey_heights_bg_unit character varying(4000),
    lod1_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod2_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod3_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod4_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod2_multi_curve public.geometry(MultiLineStringZ,3946),
    lod3_multi_curve public.geometry(MultiLineStringZ,3946),
    lod4_multi_curve public.geometry(MultiLineStringZ,3946),
    lod0_footprint_id integer,
    lod0_roofprint_id integer,
    lod1_multi_surface_id integer,
    lod2_multi_surface_id integer,
    lod3_multi_surface_id integer,
    lod4_multi_surface_id integer,
    lod1_solid_id integer,
    lod2_solid_id integer,
    lod3_solid_id integer,
    lod4_solid_id integer
);


ALTER TABLE citydb.building OWNER TO postgres;

--
-- TOC entry 232 (class 1259 OID 416323)
-- Name: building_furniture; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.building_furniture (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    room_id integer,
    lod4_brep_id integer,
    lod4_other_geom public.geometry(GeometryZ,3946),
    lod4_implicit_rep_id integer,
    lod4_implicit_ref_point public.geometry(PointZ,3946),
    lod4_implicit_transformation character varying(1000)
);


ALTER TABLE citydb.building_furniture OWNER TO postgres;

--
-- TOC entry 233 (class 1259 OID 416331)
-- Name: building_installation; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.building_installation (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    building_id integer,
    room_id integer,
    lod2_brep_id integer,
    lod3_brep_id integer,
    lod4_brep_id integer,
    lod2_other_geom public.geometry(GeometryZ,3946),
    lod3_other_geom public.geometry(GeometryZ,3946),
    lod4_other_geom public.geometry(GeometryZ,3946),
    lod2_implicit_rep_id integer,
    lod3_implicit_rep_id integer,
    lod4_implicit_rep_id integer,
    lod2_implicit_ref_point public.geometry(PointZ,3946),
    lod3_implicit_ref_point public.geometry(PointZ,3946),
    lod4_implicit_ref_point public.geometry(PointZ,3946),
    lod2_implicit_transformation character varying(1000),
    lod3_implicit_transformation character varying(1000),
    lod4_implicit_transformation character varying(1000)
);


ALTER TABLE citydb.building_installation OWNER TO postgres;

--
-- TOC entry 226 (class 1259 OID 416290)
-- Name: city_furniture; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.city_furniture (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    lod1_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod2_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod3_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod4_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod1_brep_id integer,
    lod2_brep_id integer,
    lod3_brep_id integer,
    lod4_brep_id integer,
    lod1_other_geom public.geometry(GeometryZ,3946),
    lod2_other_geom public.geometry(GeometryZ,3946),
    lod3_other_geom public.geometry(GeometryZ,3946),
    lod4_other_geom public.geometry(GeometryZ,3946),
    lod1_implicit_rep_id integer,
    lod2_implicit_rep_id integer,
    lod3_implicit_rep_id integer,
    lod4_implicit_rep_id integer,
    lod1_implicit_ref_point public.geometry(PointZ,3946),
    lod2_implicit_ref_point public.geometry(PointZ,3946),
    lod3_implicit_ref_point public.geometry(PointZ,3946),
    lod4_implicit_ref_point public.geometry(PointZ,3946),
    lod1_implicit_transformation character varying(1000),
    lod2_implicit_transformation character varying(1000),
    lod3_implicit_transformation character varying(1000),
    lod4_implicit_transformation character varying(1000)
);


ALTER TABLE citydb.city_furniture OWNER TO postgres;

--
-- TOC entry 215 (class 1259 OID 416241)
-- Name: citymodel_seq; Type: SEQUENCE; Schema: citydb; Owner: postgres
--

CREATE SEQUENCE citydb.citymodel_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE citydb.citymodel_seq OWNER TO postgres;

--
-- TOC entry 281 (class 1259 OID 416669)
-- Name: citymodel; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.citymodel (
    id integer DEFAULT nextval('citydb.citymodel_seq'::regclass) NOT NULL,
    gmlid character varying(256),
    gmlid_codespace character varying(1000),
    name character varying(1000),
    name_codespace character varying(4000),
    description character varying(4000),
    envelope public.geometry(PolygonZ,3946),
    creation_date timestamp with time zone,
    termination_date timestamp with time zone,
    last_modification_date timestamp with time zone,
    updating_person character varying(256),
    reason_for_update character varying(4000),
    lineage character varying(256)
);


ALTER TABLE citydb.citymodel OWNER TO postgres;

--
-- TOC entry 216 (class 1259 OID 416243)
-- Name: cityobject_seq; Type: SEQUENCE; Schema: citydb; Owner: postgres
--

CREATE SEQUENCE citydb.cityobject_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE citydb.cityobject_seq OWNER TO postgres;

--
-- TOC entry 275 (class 1259 OID 416615)
-- Name: cityobject; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.cityobject (
    id integer DEFAULT nextval('citydb.cityobject_seq'::regclass) NOT NULL,
    objectclass_id integer NOT NULL,
    gmlid character varying(256),
    gmlid_codespace character varying(1000),
    name character varying(1000),
    name_codespace character varying(4000),
    description character varying(4000),
    envelope public.geometry(PolygonZ,3946),
    creation_date timestamp with time zone,
    termination_date timestamp with time zone,
    relative_to_terrain character varying(256),
    relative_to_water character varying(256),
    last_modification_date timestamp with time zone,
    updating_person character varying(256),
    reason_for_update character varying(4000),
    lineage character varying(256),
    xml_source text
);


ALTER TABLE citydb.cityobject OWNER TO postgres;

--
-- TOC entry 227 (class 1259 OID 416298)
-- Name: cityobject_genericatt_seq; Type: SEQUENCE; Schema: citydb; Owner: postgres
--

CREATE SEQUENCE citydb.cityobject_genericatt_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE citydb.cityobject_genericatt_seq OWNER TO postgres;

--
-- TOC entry 282 (class 1259 OID 416678)
-- Name: cityobject_genericattrib; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.cityobject_genericattrib (
    id integer DEFAULT nextval('citydb.cityobject_genericatt_seq'::regclass) NOT NULL,
    parent_genattrib_id integer,
    root_genattrib_id integer,
    attrname character varying(256) NOT NULL,
    datatype integer,
    strval character varying(4000),
    intval integer,
    realval double precision,
    urival character varying(4000),
    dateval timestamp with time zone,
    unit character varying(4000),
    genattribset_codespace character varying(4000),
    blobval bytea,
    geomval public.geometry(GeometryZ,3946),
    surface_geometry_id integer,
    cityobject_id integer
);


ALTER TABLE citydb.cityobject_genericattrib OWNER TO postgres;

--
-- TOC entry 217 (class 1259 OID 416245)
-- Name: cityobject_member; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.cityobject_member (
    citymodel_id integer NOT NULL,
    cityobject_id integer NOT NULL
);


ALTER TABLE citydb.cityobject_member OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 416259)
-- Name: cityobjectgroup; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.cityobjectgroup (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    brep_id integer,
    other_geom public.geometry(GeometryZ,3946),
    parent_cityobject_id integer
);


ALTER TABLE citydb.cityobjectgroup OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 416272)
-- Name: database_srs; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.database_srs (
    srid integer NOT NULL,
    gml_srs_name character varying(1000)
);


ALTER TABLE citydb.database_srs OWNER TO postgres;

--
-- TOC entry 218 (class 1259 OID 416250)
-- Name: external_ref_seq; Type: SEQUENCE; Schema: citydb; Owner: postgres
--

CREATE SEQUENCE citydb.external_ref_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE citydb.external_ref_seq OWNER TO postgres;

--
-- TOC entry 283 (class 1259 OID 416687)
-- Name: external_reference; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.external_reference (
    id integer DEFAULT nextval('citydb.external_ref_seq'::regclass) NOT NULL,
    infosys character varying(4000),
    name character varying(4000),
    uri character varying(4000),
    cityobject_id integer
);


ALTER TABLE citydb.external_reference OWNER TO postgres;

--
-- TOC entry 219 (class 1259 OID 416252)
-- Name: generalization; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.generalization (
    cityobject_id integer NOT NULL,
    generalizes_to_id integer NOT NULL
);


ALTER TABLE citydb.generalization OWNER TO postgres;

--
-- TOC entry 228 (class 1259 OID 416300)
-- Name: generic_cityobject; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.generic_cityobject (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    lod0_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod1_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod2_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod3_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod4_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod0_brep_id integer,
    lod1_brep_id integer,
    lod2_brep_id integer,
    lod3_brep_id integer,
    lod4_brep_id integer,
    lod0_other_geom public.geometry(GeometryZ,3946),
    lod1_other_geom public.geometry(GeometryZ,3946),
    lod2_other_geom public.geometry(GeometryZ,3946),
    lod3_other_geom public.geometry(GeometryZ,3946),
    lod4_other_geom public.geometry(GeometryZ,3946),
    lod0_implicit_rep_id integer,
    lod1_implicit_rep_id integer,
    lod2_implicit_rep_id integer,
    lod3_implicit_rep_id integer,
    lod4_implicit_rep_id integer,
    lod0_implicit_ref_point public.geometry(PointZ,3946),
    lod1_implicit_ref_point public.geometry(PointZ,3946),
    lod2_implicit_ref_point public.geometry(PointZ,3946),
    lod3_implicit_ref_point public.geometry(PointZ,3946),
    lod4_implicit_ref_point public.geometry(PointZ,3946),
    lod0_implicit_transformation character varying(1000),
    lod1_implicit_transformation character varying(1000),
    lod2_implicit_transformation character varying(1000),
    lod3_implicit_transformation character varying(1000),
    lod4_implicit_transformation character varying(1000)
);


ALTER TABLE citydb.generic_cityobject OWNER TO postgres;

--
-- TOC entry 274 (class 1259 OID 416613)
-- Name: grid_coverage_seq; Type: SEQUENCE; Schema: citydb; Owner: postgres
--

CREATE SEQUENCE citydb.grid_coverage_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE citydb.grid_coverage_seq OWNER TO postgres;

--
-- TOC entry 285 (class 1259 OID 416705)
-- Name: grid_coverage; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.grid_coverage (
    id integer DEFAULT nextval('citydb.grid_coverage_seq'::regclass) NOT NULL,
    rasterproperty public.raster
);


ALTER TABLE citydb.grid_coverage OWNER TO postgres;

--
-- TOC entry 222 (class 1259 OID 416267)
-- Name: group_to_cityobject; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.group_to_cityobject (
    cityobject_id integer NOT NULL,
    cityobjectgroup_id integer NOT NULL,
    role character varying(256)
);


ALTER TABLE citydb.group_to_cityobject OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 416288)
-- Name: implicit_geometry_seq; Type: SEQUENCE; Schema: citydb; Owner: postgres
--

CREATE SEQUENCE citydb.implicit_geometry_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE citydb.implicit_geometry_seq OWNER TO postgres;

--
-- TOC entry 277 (class 1259 OID 416633)
-- Name: implicit_geometry; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.implicit_geometry (
    id integer DEFAULT nextval('citydb.implicit_geometry_seq'::regclass) NOT NULL,
    mime_type character varying(256),
    reference_to_library character varying(4000),
    library_object bytea,
    relative_brep_id integer,
    relative_other_geom public.geometry(GeometryZ)
);


ALTER TABLE citydb.implicit_geometry OWNER TO postgres;

--
-- TOC entry 295 (class 1259 OID 418796)
-- Name: index_table; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.index_table (
    id integer NOT NULL,
    obj citydb_pkg.index_obj
);


ALTER TABLE citydb.index_table OWNER TO postgres;

--
-- TOC entry 294 (class 1259 OID 418794)
-- Name: index_table_id_seq; Type: SEQUENCE; Schema: citydb; Owner: postgres
--

CREATE SEQUENCE citydb.index_table_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE citydb.index_table_id_seq OWNER TO postgres;

--
-- TOC entry 5616 (class 0 OID 0)
-- Dependencies: 294
-- Name: index_table_id_seq; Type: SEQUENCE OWNED BY; Schema: citydb; Owner: postgres
--

ALTER SEQUENCE citydb.index_table_id_seq OWNED BY citydb.index_table.id;


--
-- TOC entry 250 (class 1259 OID 416445)
-- Name: land_use; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.land_use (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    lod0_multi_surface_id integer,
    lod1_multi_surface_id integer,
    lod2_multi_surface_id integer,
    lod3_multi_surface_id integer,
    lod4_multi_surface_id integer
);


ALTER TABLE citydb.land_use OWNER TO postgres;

--
-- TOC entry 243 (class 1259 OID 416390)
-- Name: masspoint_relief; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.masspoint_relief (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    relief_points public.geometry(MultiPointZ,3946)
);


ALTER TABLE citydb.masspoint_relief OWNER TO postgres;

--
-- TOC entry 224 (class 1259 OID 416280)
-- Name: objectclass; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.objectclass (
    id integer NOT NULL,
    is_ade_class numeric,
    is_toplevel numeric,
    classname character varying(256),
    tablename character varying(30),
    superclass_id integer,
    baseclass_id integer,
    ade_id integer
);


ALTER TABLE citydb.objectclass OWNER TO postgres;

--
-- TOC entry 234 (class 1259 OID 416339)
-- Name: opening; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.opening (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    address_id integer,
    lod3_multi_surface_id integer,
    lod4_multi_surface_id integer,
    lod3_implicit_rep_id integer,
    lod4_implicit_rep_id integer,
    lod3_implicit_ref_point public.geometry(PointZ,3946),
    lod4_implicit_ref_point public.geometry(PointZ,3946),
    lod3_implicit_transformation character varying(1000),
    lod4_implicit_transformation character varying(1000)
);


ALTER TABLE citydb.opening OWNER TO postgres;

--
-- TOC entry 235 (class 1259 OID 416347)
-- Name: opening_to_them_surface; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.opening_to_them_surface (
    opening_id integer NOT NULL,
    thematic_surface_id integer NOT NULL
);


ALTER TABLE citydb.opening_to_them_surface OWNER TO postgres;

--
-- TOC entry 251 (class 1259 OID 416453)
-- Name: plant_cover; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.plant_cover (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    average_height double precision,
    average_height_unit character varying(4000),
    lod1_multi_surface_id integer,
    lod2_multi_surface_id integer,
    lod3_multi_surface_id integer,
    lod4_multi_surface_id integer,
    lod1_multi_solid_id integer,
    lod2_multi_solid_id integer,
    lod3_multi_solid_id integer,
    lod4_multi_solid_id integer
);


ALTER TABLE citydb.plant_cover OWNER TO postgres;

--
-- TOC entry 256 (class 1259 OID 416490)
-- Name: raster_relief; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.raster_relief (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    raster_uri character varying(4000),
    coverage_id integer
);


ALTER TABLE citydb.raster_relief OWNER TO postgres;

--
-- TOC entry 244 (class 1259 OID 416398)
-- Name: relief_component; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.relief_component (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    lod numeric,
    extent public.geometry(Polygon,3946),
    CONSTRAINT relief_comp_lod_chk CHECK (((lod >= (0)::numeric) AND (lod < (5)::numeric)))
);


ALTER TABLE citydb.relief_component OWNER TO postgres;

--
-- TOC entry 245 (class 1259 OID 416407)
-- Name: relief_feat_to_rel_comp; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.relief_feat_to_rel_comp (
    relief_component_id integer NOT NULL,
    relief_feature_id integer NOT NULL
);


ALTER TABLE citydb.relief_feat_to_rel_comp OWNER TO postgres;

--
-- TOC entry 246 (class 1259 OID 416412)
-- Name: relief_feature; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.relief_feature (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    lod numeric,
    CONSTRAINT relief_feat_lod_chk CHECK (((lod >= (0)::numeric) AND (lod < (5)::numeric)))
);


ALTER TABLE citydb.relief_feature OWNER TO postgres;

--
-- TOC entry 236 (class 1259 OID 416352)
-- Name: room; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.room (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    building_id integer,
    lod4_multi_surface_id integer,
    lod4_solid_id integer
);


ALTER TABLE citydb.room OWNER TO postgres;

--
-- TOC entry 286 (class 1259 OID 416714)
-- Name: schema_seq; Type: SEQUENCE; Schema: citydb; Owner: postgres
--

CREATE SEQUENCE citydb.schema_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE citydb.schema_seq OWNER TO postgres;

--
-- TOC entry 288 (class 1259 OID 417070)
-- Name: schema; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.schema (
    id integer DEFAULT nextval('citydb.schema_seq'::regclass) NOT NULL,
    is_ade_root numeric NOT NULL,
    citygml_version character varying(50) NOT NULL,
    xml_namespace_uri character varying(4000) NOT NULL,
    xml_namespace_prefix character varying(50) NOT NULL,
    xml_schema_location character varying(4000),
    xml_schemafile bytea,
    xml_schemafile_type character varying(256),
    ade_id integer
);


ALTER TABLE citydb.schema OWNER TO postgres;

--
-- TOC entry 290 (class 1259 OID 417087)
-- Name: schema_referencing; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.schema_referencing (
    referencing_id integer NOT NULL,
    referenced_id integer NOT NULL
);


ALTER TABLE citydb.schema_referencing OWNER TO postgres;

--
-- TOC entry 289 (class 1259 OID 417079)
-- Name: schema_to_objectclass; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.schema_to_objectclass (
    schema_id integer NOT NULL,
    objectclass_id integer NOT NULL
);


ALTER TABLE citydb.schema_to_objectclass OWNER TO postgres;

--
-- TOC entry 252 (class 1259 OID 416461)
-- Name: solitary_vegetat_object; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.solitary_vegetat_object (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    species character varying(1000),
    species_codespace character varying(4000),
    height double precision,
    height_unit character varying(4000),
    trunk_diameter double precision,
    trunk_diameter_unit character varying(4000),
    crown_diameter double precision,
    crown_diameter_unit character varying(4000),
    lod1_brep_id integer,
    lod2_brep_id integer,
    lod3_brep_id integer,
    lod4_brep_id integer,
    lod1_other_geom public.geometry(GeometryZ,3946),
    lod2_other_geom public.geometry(GeometryZ,3946),
    lod3_other_geom public.geometry(GeometryZ,3946),
    lod4_other_geom public.geometry(GeometryZ,3946),
    lod1_implicit_rep_id integer,
    lod2_implicit_rep_id integer,
    lod3_implicit_rep_id integer,
    lod4_implicit_rep_id integer,
    lod1_implicit_ref_point public.geometry(PointZ,3946),
    lod2_implicit_ref_point public.geometry(PointZ,3946),
    lod3_implicit_ref_point public.geometry(PointZ,3946),
    lod4_implicit_ref_point public.geometry(PointZ,3946),
    lod1_implicit_transformation character varying(1000),
    lod2_implicit_transformation character varying(1000),
    lod3_implicit_transformation character varying(1000),
    lod4_implicit_transformation character varying(1000)
);


ALTER TABLE citydb.solitary_vegetat_object OWNER TO postgres;

--
-- TOC entry 239 (class 1259 OID 416367)
-- Name: surface_data_seq; Type: SEQUENCE; Schema: citydb; Owner: postgres
--

CREATE SEQUENCE citydb.surface_data_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE citydb.surface_data_seq OWNER TO postgres;

--
-- TOC entry 280 (class 1259 OID 416660)
-- Name: surface_data; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.surface_data (
    id integer DEFAULT nextval('citydb.surface_data_seq'::regclass) NOT NULL,
    gmlid character varying(256),
    gmlid_codespace character varying(1000),
    name character varying(1000),
    name_codespace character varying(4000),
    description character varying(4000),
    is_front numeric,
    objectclass_id integer NOT NULL,
    x3d_shininess double precision,
    x3d_transparency double precision,
    x3d_ambient_intensity double precision,
    x3d_specular_color character varying(256),
    x3d_diffuse_color character varying(256),
    x3d_emissive_color character varying(256),
    x3d_is_smooth numeric,
    tex_image_id integer,
    tex_texture_type character varying(256),
    tex_wrap_mode character varying(256),
    tex_border_color character varying(256),
    gt_prefer_worldfile numeric,
    gt_orientation character varying(256),
    gt_reference_point public.geometry(Point,3946)
);


ALTER TABLE citydb.surface_data OWNER TO postgres;

--
-- TOC entry 220 (class 1259 OID 416257)
-- Name: surface_geometry_seq; Type: SEQUENCE; Schema: citydb; Owner: postgres
--

CREATE SEQUENCE citydb.surface_geometry_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE citydb.surface_geometry_seq OWNER TO postgres;

--
-- TOC entry 278 (class 1259 OID 416642)
-- Name: surface_geometry; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.surface_geometry (
    id integer DEFAULT nextval('citydb.surface_geometry_seq'::regclass) NOT NULL,
    gmlid character varying(256),
    gmlid_codespace character varying(1000),
    parent_id integer,
    root_id integer,
    is_solid numeric,
    is_composite numeric,
    is_triangulated numeric,
    is_xlink numeric,
    is_reverse numeric,
    solid_geometry public.geometry(PolyhedralSurfaceZ,3946),
    geometry public.geometry(PolygonZ,3946),
    implicit_geometry public.geometry(PolygonZ),
    cityobject_id integer
);


ALTER TABLE citydb.surface_geometry OWNER TO postgres;

--
-- TOC entry 261 (class 1259 OID 416524)
-- Name: tex_image_seq; Type: SEQUENCE; Schema: citydb; Owner: postgres
--

CREATE SEQUENCE citydb.tex_image_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    MAXVALUE 2147483647
    CACHE 1;


ALTER TABLE citydb.tex_image_seq OWNER TO postgres;

--
-- TOC entry 284 (class 1259 OID 416696)
-- Name: tex_image; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.tex_image (
    id integer DEFAULT nextval('citydb.tex_image_seq'::regclass) NOT NULL,
    tex_image_uri character varying(4000),
    tex_image_data bytea,
    tex_mime_type character varying(256),
    tex_mime_type_codespace character varying(4000)
);


ALTER TABLE citydb.tex_image OWNER TO postgres;

--
-- TOC entry 240 (class 1259 OID 416369)
-- Name: textureparam; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.textureparam (
    surface_geometry_id integer NOT NULL,
    is_texture_parametrization numeric,
    world_to_texture character varying(1000),
    texture_coordinates public.geometry(Polygon),
    surface_data_id integer NOT NULL
);


ALTER TABLE citydb.textureparam OWNER TO postgres;

--
-- TOC entry 237 (class 1259 OID 416360)
-- Name: thematic_surface; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.thematic_surface (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    building_id integer,
    room_id integer,
    building_installation_id integer,
    lod2_multi_surface_id integer,
    lod3_multi_surface_id integer,
    lod4_multi_surface_id integer
);


ALTER TABLE citydb.thematic_surface OWNER TO postgres;

--
-- TOC entry 247 (class 1259 OID 416421)
-- Name: tin_relief; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.tin_relief (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    max_length double precision,
    max_length_unit character varying(4000),
    stop_lines public.geometry(MultiLineStringZ,3946),
    break_lines public.geometry(MultiLineStringZ,3946),
    control_points public.geometry(MultiPointZ,3946),
    surface_geometry_id integer
);


ALTER TABLE citydb.tin_relief OWNER TO postgres;

--
-- TOC entry 249 (class 1259 OID 416437)
-- Name: traffic_area; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.traffic_area (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    surface_material character varying(256),
    surface_material_codespace character varying(4000),
    lod2_multi_surface_id integer,
    lod3_multi_surface_id integer,
    lod4_multi_surface_id integer,
    transportation_complex_id integer
);


ALTER TABLE citydb.traffic_area OWNER TO postgres;

--
-- TOC entry 248 (class 1259 OID 416429)
-- Name: transportation_complex; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.transportation_complex (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    lod0_network public.geometry(GeometryZ,3946),
    lod1_multi_surface_id integer,
    lod2_multi_surface_id integer,
    lod3_multi_surface_id integer,
    lod4_multi_surface_id integer
);


ALTER TABLE citydb.transportation_complex OWNER TO postgres;

--
-- TOC entry 257 (class 1259 OID 416498)
-- Name: tunnel; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.tunnel (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    tunnel_parent_id integer,
    tunnel_root_id integer,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    year_of_construction date,
    year_of_demolition date,
    lod1_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod2_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod3_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod4_terrain_intersection public.geometry(MultiLineStringZ,3946),
    lod2_multi_curve public.geometry(MultiLineStringZ,3946),
    lod3_multi_curve public.geometry(MultiLineStringZ,3946),
    lod4_multi_curve public.geometry(MultiLineStringZ,3946),
    lod1_multi_surface_id integer,
    lod2_multi_surface_id integer,
    lod3_multi_surface_id integer,
    lod4_multi_surface_id integer,
    lod1_solid_id integer,
    lod2_solid_id integer,
    lod3_solid_id integer,
    lod4_solid_id integer
);


ALTER TABLE citydb.tunnel OWNER TO postgres;

--
-- TOC entry 264 (class 1259 OID 416542)
-- Name: tunnel_furniture; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.tunnel_furniture (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    tunnel_hollow_space_id integer,
    lod4_brep_id integer,
    lod4_other_geom public.geometry(GeometryZ,3946),
    lod4_implicit_rep_id integer,
    lod4_implicit_ref_point public.geometry(PointZ,3946),
    lod4_implicit_transformation character varying(1000)
);


ALTER TABLE citydb.tunnel_furniture OWNER TO postgres;

--
-- TOC entry 259 (class 1259 OID 416511)
-- Name: tunnel_hollow_space; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.tunnel_hollow_space (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    tunnel_id integer,
    lod4_multi_surface_id integer,
    lod4_solid_id integer
);


ALTER TABLE citydb.tunnel_hollow_space OWNER TO postgres;

--
-- TOC entry 263 (class 1259 OID 416534)
-- Name: tunnel_installation; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.tunnel_installation (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    tunnel_id integer,
    tunnel_hollow_space_id integer,
    lod2_brep_id integer,
    lod3_brep_id integer,
    lod4_brep_id integer,
    lod2_other_geom public.geometry(GeometryZ,3946),
    lod3_other_geom public.geometry(GeometryZ,3946),
    lod4_other_geom public.geometry(GeometryZ,3946),
    lod2_implicit_rep_id integer,
    lod3_implicit_rep_id integer,
    lod4_implicit_rep_id integer,
    lod2_implicit_ref_point public.geometry(PointZ,3946),
    lod3_implicit_ref_point public.geometry(PointZ,3946),
    lod4_implicit_ref_point public.geometry(PointZ,3946),
    lod2_implicit_transformation character varying(1000),
    lod3_implicit_transformation character varying(1000),
    lod4_implicit_transformation character varying(1000)
);


ALTER TABLE citydb.tunnel_installation OWNER TO postgres;

--
-- TOC entry 258 (class 1259 OID 416506)
-- Name: tunnel_open_to_them_srf; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.tunnel_open_to_them_srf (
    tunnel_opening_id integer NOT NULL,
    tunnel_thematic_surface_id integer NOT NULL
);


ALTER TABLE citydb.tunnel_open_to_them_srf OWNER TO postgres;

--
-- TOC entry 262 (class 1259 OID 416526)
-- Name: tunnel_opening; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.tunnel_opening (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    lod3_multi_surface_id integer,
    lod4_multi_surface_id integer,
    lod3_implicit_rep_id integer,
    lod4_implicit_rep_id integer,
    lod3_implicit_ref_point public.geometry(PointZ,3946),
    lod4_implicit_ref_point public.geometry(PointZ,3946),
    lod3_implicit_transformation character varying(1000),
    lod4_implicit_transformation character varying(1000)
);


ALTER TABLE citydb.tunnel_opening OWNER TO postgres;

--
-- TOC entry 260 (class 1259 OID 416519)
-- Name: tunnel_thematic_surface; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.tunnel_thematic_surface (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    tunnel_id integer,
    tunnel_hollow_space_id integer,
    tunnel_installation_id integer,
    lod2_multi_surface_id integer,
    lod3_multi_surface_id integer,
    lod4_multi_surface_id integer
);


ALTER TABLE citydb.tunnel_thematic_surface OWNER TO postgres;

--
-- TOC entry 254 (class 1259 OID 416477)
-- Name: waterbod_to_waterbnd_srf; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.waterbod_to_waterbnd_srf (
    waterboundary_surface_id integer NOT NULL,
    waterbody_id integer NOT NULL
);


ALTER TABLE citydb.waterbod_to_waterbnd_srf OWNER TO postgres;

--
-- TOC entry 253 (class 1259 OID 416469)
-- Name: waterbody; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.waterbody (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    lod0_multi_curve public.geometry(MultiLineStringZ,3946),
    lod1_multi_curve public.geometry(MultiLineStringZ,3946),
    lod0_multi_surface_id integer,
    lod1_multi_surface_id integer,
    lod1_solid_id integer,
    lod2_solid_id integer,
    lod3_solid_id integer,
    lod4_solid_id integer
);


ALTER TABLE citydb.waterbody OWNER TO postgres;

--
-- TOC entry 255 (class 1259 OID 416482)
-- Name: waterboundary_surface; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.waterboundary_surface (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    water_level character varying(256),
    water_level_codespace character varying(4000),
    lod2_surface_id integer,
    lod3_surface_id integer,
    lod4_surface_id integer
);


ALTER TABLE citydb.waterboundary_surface OWNER TO postgres;

--
-- TOC entry 4588 (class 2604 OID 418799)
-- Name: index_table id; Type: DEFAULT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.index_table ALTER COLUMN id SET DEFAULT nextval('citydb.index_table_id_seq'::regclass);


--
-- TOC entry 5590 (class 0 OID 416651)
-- Dependencies: 279
-- Data for Name: address; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.address (id, gmlid, gmlid_codespace, street, house_number, po_box, zip_code, city, state, country, multi_point, xal_source) FROM stdin;
\.


--
-- TOC entry 5584 (class 0 OID 416608)
-- Dependencies: 273
-- Data for Name: address_to_bridge; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.address_to_bridge (bridge_id, address_id) FROM stdin;
\.


--
-- TOC entry 5541 (class 0 OID 416310)
-- Dependencies: 230
-- Data for Name: address_to_building; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.address_to_building (building_id, address_id) FROM stdin;
\.


--
-- TOC entry 5602 (class 0 OID 417116)
-- Dependencies: 291
-- Data for Name: ade; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.ade (id, adeid, name, description, version, db_prefix, xml_schemamapping_file, drop_db_script, creation_date, creation_person) FROM stdin;
\.


--
-- TOC entry 5603 (class 0 OID 417126)
-- Dependencies: 292
-- Data for Name: aggregation_info; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) FROM stdin;
3	57	cityobject_member	0	\N	0
110	3	cityobject_id	0	\N	1
106	108	root_id	0	\N	1
106	108	parent_id	0	\N	1
106	59	relative_brep_id	0	1	1
50	57	citymodel_id	0	\N	1
50	3	cityobject_id	0	\N	1
51	50	appear_to_surface_data	0	\N	0
109	51	tex_image_id	0	1	0
3	23	group_to_cityobject	0	\N	0
106	23	brep_id	0	1	1
59	21	lod1_implicit_rep_id	0	1	0
59	21	lod2_implicit_rep_id	0	1	0
59	21	lod3_implicit_rep_id	0	1	0
59	21	lod4_implicit_rep_id	0	1	0
106	21	lod1_brep_id	0	1	1
106	21	lod2_brep_id	0	1	1
106	21	lod3_brep_id	0	1	1
106	21	lod4_brep_id	0	1	1
112	113	parent_genattrib_id	0	\N	1
112	113	root_genattrib_id	0	\N	1
112	3	cityobject_id	0	\N	1
106	112	surface_geometry_id	0	1	1
106	5	lod0_brep_id	0	1	1
106	5	lod1_brep_id	0	1	1
106	5	lod2_brep_id	0	1	1
106	5	lod3_brep_id	0	1	1
106	5	lod4_brep_id	0	1	1
59	5	lod0_implicit_rep_id	0	1	0
59	5	lod1_implicit_rep_id	0	1	0
59	5	lod2_implicit_rep_id	0	1	0
59	5	lod3_implicit_rep_id	0	1	0
59	5	lod4_implicit_rep_id	0	1	0
106	4	lod0_multi_surface_id	0	1	1
106	4	lod1_multi_surface_id	0	1	1
106	4	lod2_multi_surface_id	0	1	1
106	4	lod3_multi_surface_id	0	1	1
106	4	lod4_multi_surface_id	0	1	1
15	14	relief_feat_to_rel_comp	0	\N	0
106	16	surface_geometry_id	0	1	1
111	19	coverage_id	0	1	1
47	42	transportation_complex_id	0	\N	1
106	47	lod2_multi_surface_id	0	1	1
106	47	lod3_multi_surface_id	0	1	1
106	47	lod4_multi_surface_id	0	1	1
106	42	lod1_multi_surface_id	0	1	1
106	42	lod2_multi_surface_id	0	1	1
106	42	lod3_multi_surface_id	0	1	1
106	42	lod4_multi_surface_id	0	1	1
106	7	lod1_brep_id	0	1	1
106	7	lod2_brep_id	0	1	1
106	7	lod3_brep_id	0	1	1
106	7	lod4_brep_id	0	1	1
59	7	lod1_implicit_rep_id	0	1	0
59	7	lod2_implicit_rep_id	0	1	0
59	7	lod3_implicit_rep_id	0	1	0
59	7	lod4_implicit_rep_id	0	1	0
106	8	lod1_multi_surface_id	0	1	1
106	8	lod2_multi_surface_id	0	1	1
106	8	lod3_multi_surface_id	0	1	1
106	8	lod4_multi_surface_id	0	1	1
106	8	lod1_multi_solid_id	0	1	1
106	8	lod2_multi_solid_id	0	1	1
106	8	lod3_multi_solid_id	0	1	1
106	8	lod4_multi_solid_id	0	1	1
10	9	waterbod_to_waterbnd_srf	0	\N	0
106	9	lod0_multi_surface_id	0	1	1
106	9	lod1_multi_surface_id	0	1	1
106	9	lod1_solid_id	0	1	1
106	9	lod2_solid_id	0	1	1
106	9	lod3_solid_id	0	1	1
106	9	lod4_solid_id	0	1	1
106	10	lod2_surface_id	0	1	1
106	10	lod3_surface_id	0	1	1
106	10	lod4_surface_id	0	1	1
58	62	address_to_bridge	0	\N	0
58	77	address_id	0	1	0
63	62	bridge_parent_id	0	\N	1
63	64	bridge_root_id	0	\N	1
82	62	bridge_id	0	\N	1
80	81	bridge_room_id	0	\N	1
66	81	bridge_room_id	0	\N	1
65	62	bridge_id	0	\N	1
77	67	bridge_open_to_them_srf	0	\N	1
81	62	bridge_id	0	\N	1
67	81	bridge_room_id	0	\N	1
67	62	bridge_id	0	\N	1
67	65	bridge_installation_id	0	\N	1
106	62	lod1_multi_surface_id	0	1	1
106	62	lod2_multi_surface_id	0	1	1
106	62	lod3_multi_surface_id	0	1	1
106	62	lod4_multi_surface_id	0	1	1
106	62	lod1_solid_id	0	1	1
106	62	lod2_solid_id	0	1	1
106	62	lod3_solid_id	0	1	1
106	62	lod4_solid_id	0	1	1
106	80	lod4_brep_id	0	1	1
106	65	lod2_brep_id	0	1	1
106	65	lod3_brep_id	0	1	1
106	65	lod4_brep_id	0	1	1
106	66	lod4_brep_id	0	1	1
106	77	lod3_multi_surface_id	0	1	1
106	77	lod4_multi_surface_id	0	1	1
106	67	lod2_multi_surface_id	0	1	1
106	67	lod3_multi_surface_id	0	1	1
106	67	lod4_multi_surface_id	0	1	1
106	81	lod4_multi_surface_id	0	1	1
106	81	lod4_solid_id	0	1	1
106	82	lod1_brep_id	0	1	1
106	82	lod2_brep_id	0	1	1
106	82	lod3_brep_id	0	1	1
106	82	lod4_brep_id	0	1	1
59	80	lod4_implicit_rep_id	0	1	0
59	65	lod2_implicit_rep_id	0	1	0
59	65	lod3_implicit_rep_id	0	1	0
59	65	lod4_implicit_rep_id	0	1	0
59	66	lod4_implicit_rep_id	0	1	0
59	77	lod3_implicit_rep_id	0	1	0
59	77	lod4_implicit_rep_id	0	1	0
59	82	lod1_implicit_rep_id	0	1	0
59	82	lod2_implicit_rep_id	0	1	0
59	82	lod3_implicit_rep_id	0	1	0
59	82	lod4_implicit_rep_id	0	1	0
58	24	address_to_building	0	\N	0
58	37	address_id	0	1	0
25	24	building_parent_id	0	\N	1
25	26	building_root_id	0	\N	1
40	41	room_id	0	\N	1
28	41	room_id	0	\N	1
27	24	building_id	0	\N	1
37	29	opening_to_them_surface	0	\N	1
41	24	building_id	0	\N	1
29	41	room_id	0	\N	1
29	27	building_installation_id	0	\N	1
29	24	building_id	0	\N	1
106	24	lod0_footprint_id	0	1	1
106	24	lod0_roofprint_id	0	1	1
106	24	lod1_multi_surface_id	0	1	1
106	24	lod2_multi_surface_id	0	1	1
106	24	lod3_multi_surface_id	0	1	1
106	24	lod4_multi_surface_id	0	1	1
106	24	lod1_solid_id	0	1	1
106	24	lod2_solid_id	0	1	1
106	24	lod3_solid_id	0	1	1
106	24	lod4_solid_id	0	1	1
106	40	lod4_brep_id	0	1	1
106	27	lod2_brep_id	0	1	1
106	27	lod3_brep_id	0	1	1
106	27	lod4_brep_id	0	1	1
106	28	lod4_brep_id	0	1	1
106	37	lod3_multi_surface_id	0	1	1
106	37	lod4_multi_surface_id	0	1	1
106	29	lod2_multi_surface_id	0	1	1
106	29	lod3_multi_surface_id	0	1	1
106	29	lod4_multi_surface_id	0	1	1
106	41	lod4_multi_surface_id	0	1	1
106	41	lod4_solid_id	0	1	1
59	40	lod4_implicit_rep_id	0	1	0
59	27	lod2_implicit_rep_id	0	1	0
59	27	lod3_implicit_rep_id	0	1	0
59	27	lod4_implicit_rep_id	0	1	0
59	28	lod4_implicit_rep_id	0	1	0
59	37	lod3_implicit_rep_id	0	1	0
59	37	lod4_implicit_rep_id	0	1	0
84	83	tunnel_parent_id	0	\N	1
84	85	tunnel_root_id	0	\N	1
101	102	tunnel_hollow_space_id	0	\N	1
87	102	tunnel_hollow_space_id	0	\N	1
86	83	tunnel_id	0	\N	1
98	88	tunnel_open_to_them_srf	0	\N	1
102	83	tunnel_id	0	\N	1
88	102	tunnel_hollow_space_id	0	\N	1
88	83	tunnel_id	0	\N	1
88	86	tunnel_installation_id	0	\N	1
106	83	lod1_multi_surface_id	0	1	1
106	83	lod2_multi_surface_id	0	1	1
106	83	lod3_multi_surface_id	0	1	1
106	83	lod4_multi_surface_id	0	1	1
106	83	lod1_solid_id	0	1	1
106	83	lod2_solid_id	0	1	1
106	83	lod3_solid_id	0	1	1
106	83	lod4_solid_id	0	1	1
106	101	lod4_brep_id	0	1	1
106	86	lod2_brep_id	0	1	1
106	86	lod3_brep_id	0	1	1
106	86	lod4_brep_id	0	1	1
106	87	lod4_brep_id	0	1	1
106	98	lod3_multi_surface_id	0	1	1
106	98	lod4_multi_surface_id	0	1	1
106	88	lod2_multi_surface_id	0	1	1
106	88	lod3_multi_surface_id	0	1	1
106	88	lod4_multi_surface_id	0	1	1
106	102	lod4_multi_surface_id	0	1	1
106	102	lod4_solid_id	0	1	1
59	101	lod4_implicit_rep_id	0	1	0
59	86	lod2_implicit_rep_id	0	1	0
59	86	lod3_implicit_rep_id	0	1	0
59	86	lod4_implicit_rep_id	0	1	0
59	87	lod4_implicit_rep_id	0	1	0
59	98	lod3_implicit_rep_id	0	1	0
59	98	lod4_implicit_rep_id	0	1	0
\.


--
-- TOC entry 5552 (class 0 OID 416377)
-- Dependencies: 241
-- Data for Name: appear_to_surface_data; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.appear_to_surface_data (surface_data_id, appearance_id) FROM stdin;
\.


--
-- TOC entry 5587 (class 0 OID 416624)
-- Dependencies: 276
-- Data for Name: appearance; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.appearance (id, gmlid, gmlid_codespace, name, name_codespace, description, theme, citymodel_id, cityobject_id) FROM stdin;
\.


--
-- TOC entry 5553 (class 0 OID 416382)
-- Dependencies: 242
-- Data for Name: breakline_relief; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.breakline_relief (id, objectclass_id, ridge_or_valley_lines, break_lines) FROM stdin;
\.


--
-- TOC entry 5576 (class 0 OID 416550)
-- Dependencies: 265
-- Data for Name: bridge; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.bridge (id, objectclass_id, bridge_parent_id, bridge_root_id, class, class_codespace, function, function_codespace, usage, usage_codespace, year_of_construction, year_of_demolition, is_movable, lod1_terrain_intersection, lod2_terrain_intersection, lod3_terrain_intersection, lod4_terrain_intersection, lod2_multi_curve, lod3_multi_curve, lod4_multi_curve, lod1_multi_surface_id, lod2_multi_surface_id, lod3_multi_surface_id, lod4_multi_surface_id, lod1_solid_id, lod2_solid_id, lod3_solid_id, lod4_solid_id) FROM stdin;
\.


--
-- TOC entry 5583 (class 0 OID 416600)
-- Dependencies: 272
-- Data for Name: bridge_constr_element; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.bridge_constr_element (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, bridge_id, lod1_terrain_intersection, lod2_terrain_intersection, lod3_terrain_intersection, lod4_terrain_intersection, lod1_brep_id, lod2_brep_id, lod3_brep_id, lod4_brep_id, lod1_other_geom, lod2_other_geom, lod3_other_geom, lod4_other_geom, lod1_implicit_rep_id, lod2_implicit_rep_id, lod3_implicit_rep_id, lod4_implicit_rep_id, lod1_implicit_ref_point, lod2_implicit_ref_point, lod3_implicit_ref_point, lod4_implicit_ref_point, lod1_implicit_transformation, lod2_implicit_transformation, lod3_implicit_transformation, lod4_implicit_transformation) FROM stdin;
\.


--
-- TOC entry 5577 (class 0 OID 416558)
-- Dependencies: 266
-- Data for Name: bridge_furniture; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.bridge_furniture (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, bridge_room_id, lod4_brep_id, lod4_other_geom, lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) FROM stdin;
\.


--
-- TOC entry 5578 (class 0 OID 416566)
-- Dependencies: 267
-- Data for Name: bridge_installation; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.bridge_installation (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, bridge_id, bridge_room_id, lod2_brep_id, lod3_brep_id, lod4_brep_id, lod2_other_geom, lod3_other_geom, lod4_other_geom, lod2_implicit_rep_id, lod3_implicit_rep_id, lod4_implicit_rep_id, lod2_implicit_ref_point, lod3_implicit_ref_point, lod4_implicit_ref_point, lod2_implicit_transformation, lod3_implicit_transformation, lod4_implicit_transformation) FROM stdin;
\.


--
-- TOC entry 5580 (class 0 OID 416582)
-- Dependencies: 269
-- Data for Name: bridge_open_to_them_srf; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.bridge_open_to_them_srf (bridge_opening_id, bridge_thematic_surface_id) FROM stdin;
\.


--
-- TOC entry 5579 (class 0 OID 416574)
-- Dependencies: 268
-- Data for Name: bridge_opening; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.bridge_opening (id, objectclass_id, address_id, lod3_multi_surface_id, lod4_multi_surface_id, lod3_implicit_rep_id, lod4_implicit_rep_id, lod3_implicit_ref_point, lod4_implicit_ref_point, lod3_implicit_transformation, lod4_implicit_transformation) FROM stdin;
\.


--
-- TOC entry 5581 (class 0 OID 416587)
-- Dependencies: 270
-- Data for Name: bridge_room; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.bridge_room (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, bridge_id, lod4_multi_surface_id, lod4_solid_id) FROM stdin;
\.


--
-- TOC entry 5582 (class 0 OID 416595)
-- Dependencies: 271
-- Data for Name: bridge_thematic_surface; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.bridge_thematic_surface (id, objectclass_id, bridge_id, bridge_room_id, bridge_installation_id, bridge_constr_element_id, lod2_multi_surface_id, lod3_multi_surface_id, lod4_multi_surface_id) FROM stdin;
\.


--
-- TOC entry 5542 (class 0 OID 416315)
-- Dependencies: 231
-- Data for Name: building; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.building (id, objectclass_id, building_parent_id, building_root_id, class, class_codespace, function, function_codespace, usage, usage_codespace, year_of_construction, year_of_demolition, roof_type, roof_type_codespace, measured_height, measured_height_unit, storeys_above_ground, storeys_below_ground, storey_heights_above_ground, storey_heights_ag_unit, storey_heights_below_ground, storey_heights_bg_unit, lod1_terrain_intersection, lod2_terrain_intersection, lod3_terrain_intersection, lod4_terrain_intersection, lod2_multi_curve, lod3_multi_curve, lod4_multi_curve, lod0_footprint_id, lod0_roofprint_id, lod1_multi_surface_id, lod2_multi_surface_id, lod3_multi_surface_id, lod4_multi_surface_id, lod1_solid_id, lod2_solid_id, lod3_solid_id, lod4_solid_id) FROM stdin;
1	26	\N	1	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N
\.


--
-- TOC entry 5543 (class 0 OID 416323)
-- Dependencies: 232
-- Data for Name: building_furniture; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.building_furniture (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, room_id, lod4_brep_id, lod4_other_geom, lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) FROM stdin;
\.


--
-- TOC entry 5544 (class 0 OID 416331)
-- Dependencies: 233
-- Data for Name: building_installation; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.building_installation (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, building_id, room_id, lod2_brep_id, lod3_brep_id, lod4_brep_id, lod2_other_geom, lod3_other_geom, lod4_other_geom, lod2_implicit_rep_id, lod3_implicit_rep_id, lod4_implicit_rep_id, lod2_implicit_ref_point, lod3_implicit_ref_point, lod4_implicit_ref_point, lod2_implicit_transformation, lod3_implicit_transformation, lod4_implicit_transformation) FROM stdin;
\.


--
-- TOC entry 5537 (class 0 OID 416290)
-- Dependencies: 226
-- Data for Name: city_furniture; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.city_furniture (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, lod1_terrain_intersection, lod2_terrain_intersection, lod3_terrain_intersection, lod4_terrain_intersection, lod1_brep_id, lod2_brep_id, lod3_brep_id, lod4_brep_id, lod1_other_geom, lod2_other_geom, lod3_other_geom, lod4_other_geom, lod1_implicit_rep_id, lod2_implicit_rep_id, lod3_implicit_rep_id, lod4_implicit_rep_id, lod1_implicit_ref_point, lod2_implicit_ref_point, lod3_implicit_ref_point, lod4_implicit_ref_point, lod1_implicit_transformation, lod2_implicit_transformation, lod3_implicit_transformation, lod4_implicit_transformation) FROM stdin;
\.


--
-- TOC entry 5592 (class 0 OID 416669)
-- Dependencies: 281
-- Data for Name: citymodel; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.citymodel (id, gmlid, gmlid_codespace, name, name_codespace, description, envelope, creation_date, termination_date, last_modification_date, updating_person, reason_for_update, lineage) FROM stdin;
\.


--
-- TOC entry 5586 (class 0 OID 416615)
-- Dependencies: 275
-- Data for Name: cityobject; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.cityobject (id, objectclass_id, gmlid, gmlid_codespace, name, name_codespace, description, envelope, creation_date, termination_date, relative_to_terrain, relative_to_water, last_modification_date, updating_person, reason_for_update, lineage, xml_source) FROM stdin;
1	26	LYON_1_00056_0	\N	\N	\N	\N	01030000A06A0F000001000000050000001E34BBC6731E3C41FF756EBD43BE53415130630A56F864402F302BD0841E3C41FF756EBD43BE53415130630A56F864402F302BD0841E3C4166BD18AF4DBE534166834C3272A167401E34BBC6731E3C4166BD18AF4DBE534166834C3272A167401E34BBC6731E3C41FF756EBD43BE53415130630A56F86440	2021-09-13 14:04:58.395+02	\N	\N	\N	2021-09-13 14:04:58.395+02	postgres	\N	\N	\N
2	33	LYON_1_00056_0_Roof	\N	\N	\N	\N	01030000A06A0F00000100000005000000EEB5A0D7761E3C41FF756EBD43BE534166834C3272A167402F302BD0841E3C41FF756EBD43BE534166834C3272A167402F302BD0841E3C41B03BDDFF43BE534166834C3272A16740EEB5A0D7761E3C41B03BDDFF43BE534166834C3272A16740EEB5A0D7761E3C41FF756EBD43BE534166834C3272A16740	2021-09-13 14:04:58.401+02	\N	\N	\N	2021-09-13 14:04:58.401+02	postgres	\N	\N	\N
3	34	LYON_1_00056_0_Wall	\N	\N	\N	\N	01030000A06A0F000001000000050000001E34BBC6731E3C41D105F57B44BE53415130630A56F86440F3751966741E3C41D105F57B44BE53415130630A56F86440F3751966741E3C4166BD18AF4DBE534166834C3272A167401E34BBC6731E3C4166BD18AF4DBE534166834C3272A167401E34BBC6731E3C41D105F57B44BE53415130630A56F86440	2021-09-13 14:04:58.403+02	\N	\N	\N	2021-09-13 14:04:58.403+02	postgres	\N	\N	\N
\.


--
-- TOC entry 5593 (class 0 OID 416678)
-- Dependencies: 282
-- Data for Name: cityobject_genericattrib; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.cityobject_genericattrib (id, parent_genattrib_id, root_genattrib_id, attrname, datatype, strval, intval, realval, urival, dateval, unit, genattribset_codespace, blobval, geomval, surface_geometry_id, cityobject_id) FROM stdin;
\.


--
-- TOC entry 5528 (class 0 OID 416245)
-- Dependencies: 217
-- Data for Name: cityobject_member; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.cityobject_member (citymodel_id, cityobject_id) FROM stdin;
\.


--
-- TOC entry 5532 (class 0 OID 416259)
-- Dependencies: 221
-- Data for Name: cityobjectgroup; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.cityobjectgroup (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, brep_id, other_geom, parent_cityobject_id) FROM stdin;
\.


--
-- TOC entry 5534 (class 0 OID 416272)
-- Dependencies: 223
-- Data for Name: database_srs; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.database_srs (srid, gml_srs_name) FROM stdin;
3946	urn:ogc:def:crs:EPSG::3946
\.


--
-- TOC entry 5594 (class 0 OID 416687)
-- Dependencies: 283
-- Data for Name: external_reference; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.external_reference (id, infosys, name, uri, cityobject_id) FROM stdin;
\.


--
-- TOC entry 5530 (class 0 OID 416252)
-- Dependencies: 219
-- Data for Name: generalization; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.generalization (cityobject_id, generalizes_to_id) FROM stdin;
\.


--
-- TOC entry 5539 (class 0 OID 416300)
-- Dependencies: 228
-- Data for Name: generic_cityobject; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.generic_cityobject (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, lod0_terrain_intersection, lod1_terrain_intersection, lod2_terrain_intersection, lod3_terrain_intersection, lod4_terrain_intersection, lod0_brep_id, lod1_brep_id, lod2_brep_id, lod3_brep_id, lod4_brep_id, lod0_other_geom, lod1_other_geom, lod2_other_geom, lod3_other_geom, lod4_other_geom, lod0_implicit_rep_id, lod1_implicit_rep_id, lod2_implicit_rep_id, lod3_implicit_rep_id, lod4_implicit_rep_id, lod0_implicit_ref_point, lod1_implicit_ref_point, lod2_implicit_ref_point, lod3_implicit_ref_point, lod4_implicit_ref_point, lod0_implicit_transformation, lod1_implicit_transformation, lod2_implicit_transformation, lod3_implicit_transformation, lod4_implicit_transformation) FROM stdin;
\.


--
-- TOC entry 5596 (class 0 OID 416705)
-- Dependencies: 285
-- Data for Name: grid_coverage; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.grid_coverage (id, rasterproperty) FROM stdin;
\.


--
-- TOC entry 5533 (class 0 OID 416267)
-- Dependencies: 222
-- Data for Name: group_to_cityobject; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.group_to_cityobject (cityobject_id, cityobjectgroup_id, role) FROM stdin;
\.


--
-- TOC entry 5588 (class 0 OID 416633)
-- Dependencies: 277
-- Data for Name: implicit_geometry; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.implicit_geometry (id, mime_type, reference_to_library, library_object, relative_brep_id, relative_other_geom) FROM stdin;
\.


--
-- TOC entry 5605 (class 0 OID 418796)
-- Dependencies: 295
-- Data for Name: index_table; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.index_table (id, obj) FROM stdin;
1	(cityobject_envelope_spx,cityobject,envelope,1,0,0)
2	(surface_geom_spx,surface_geometry,geometry,1,0,0)
3	(surface_geom_solid_spx,surface_geometry,solid_geometry,1,0,0)
4	(cityobject_inx,cityobject,"gmlid, gmlid_codespace",0,0,0)
5	(cityobject_lineage_inx,cityobject,lineage,0,0,0)
6	(cityobj_creation_date_inx,cityobject,creation_date,0,0,0)
7	(cityobj_term_date_inx,cityobject,termination_date,0,0,0)
8	(cityobj_last_mod_date_inx,cityobject,last_modification_date,0,0,0)
9	(surface_geom_inx,surface_geometry,"gmlid, gmlid_codespace",0,0,0)
10	(appearance_inx,appearance,"gmlid, gmlid_codespace",0,0,0)
11	(appearance_theme_inx,appearance,theme,0,0,0)
12	(surface_data_inx,surface_data,"gmlid, gmlid_codespace",0,0,0)
13	(address_inx,address,"gmlid, gmlid_codespace",0,0,0)
\.


--
-- TOC entry 5561 (class 0 OID 416445)
-- Dependencies: 250
-- Data for Name: land_use; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.land_use (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, lod0_multi_surface_id, lod1_multi_surface_id, lod2_multi_surface_id, lod3_multi_surface_id, lod4_multi_surface_id) FROM stdin;
\.


--
-- TOC entry 5554 (class 0 OID 416390)
-- Dependencies: 243
-- Data for Name: masspoint_relief; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.masspoint_relief (id, objectclass_id, relief_points) FROM stdin;
\.


--
-- TOC entry 5535 (class 0 OID 416280)
-- Dependencies: 224
-- Data for Name: objectclass; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) FROM stdin;
0	0	0	Undefined	\N	\N	\N	\N
1	0	0	_GML	cityobject	\N	\N	\N
2	0	0	_Feature	cityobject	1	1	\N
3	0	0	_CityObject	cityobject	2	2	\N
4	0	1	LandUse	land_use	3	3	\N
5	0	1	GenericCityObject	generic_cityobject	3	3	\N
6	0	0	_VegetationObject	cityobject	3	3	\N
7	0	1	SolitaryVegetationObject	solitary_vegetat_object	6	3	\N
8	0	1	PlantCover	plant_cover	6	3	\N
105	0	0	_WaterObject	cityobject	3	3	\N
9	0	1	WaterBody	waterbody	105	3	\N
10	0	0	_WaterBoundarySurface	waterboundary_surface	3	3	\N
11	0	0	WaterSurface	waterboundary_surface	10	3	\N
12	0	0	WaterGroundSurface	waterboundary_surface	10	3	\N
13	0	0	WaterClosureSurface	waterboundary_surface	10	3	\N
14	0	1	ReliefFeature	relief_feature	3	3	\N
15	0	0	_ReliefComponent	relief_component	3	3	\N
16	0	0	TINRelief	tin_relief	15	3	\N
17	0	0	MassPointRelief	masspoint_relief	15	3	\N
18	0	0	BreaklineRelief	breakline_relief	15	3	\N
19	0	0	RasterRelief	raster_relief	15	3	\N
20	0	0	_Site	cityobject	3	3	\N
21	0	1	CityFurniture	city_furniture	3	3	\N
22	0	0	_TransportationObject	cityobject	3	3	\N
23	0	1	CityObjectGroup	cityobjectgroup	3	3	\N
24	0	0	_AbstractBuilding	building	20	3	\N
25	0	0	BuildingPart	building	24	3	\N
26	0	1	Building	building	24	3	\N
27	0	0	BuildingInstallation	building_installation	3	3	\N
28	0	0	IntBuildingInstallation	building_installation	3	3	\N
29	0	0	_BuildingBoundarySurface	thematic_surface	3	3	\N
30	0	0	BuildingCeilingSurface	thematic_surface	29	3	\N
31	0	0	InteriorBuildingWallSurface	thematic_surface	29	3	\N
32	0	0	BuildingFloorSurface	thematic_surface	29	3	\N
33	0	0	BuildingRoofSurface	thematic_surface	29	3	\N
34	0	0	BuildingWallSurface	thematic_surface	29	3	\N
35	0	0	BuildingGroundSurface	thematic_surface	29	3	\N
36	0	0	BuildingClosureSurface	thematic_surface	29	3	\N
37	0	0	_BuildingOpening	opening	3	3	\N
38	0	0	BuildingWindow	opening	37	3	\N
39	0	0	BuildingDoor	opening	37	3	\N
40	0	0	BuildingFurniture	building_furniture	3	3	\N
41	0	0	BuildingRoom	room	3	3	\N
42	0	1	TransportationComplex	transportation_complex	22	3	\N
43	0	1	Track	transportation_complex	42	3	\N
44	0	1	Railway	transportation_complex	42	3	\N
45	0	1	Road	transportation_complex	42	3	\N
46	0	1	Square	transportation_complex	42	3	\N
47	0	0	TrafficArea	traffic_area	22	3	\N
48	0	0	AuxiliaryTrafficArea	traffic_area	22	3	\N
49	0	0	FeatureCollection	cityobject	2	2	\N
50	0	0	Appearance	appearance	2	2	\N
51	0	0	_SurfaceData	surface_data	2	2	\N
52	0	0	_Texture	surface_data	51	2	\N
53	0	0	X3DMaterial	surface_data	51	2	\N
54	0	0	ParameterizedTexture	surface_data	52	2	\N
55	0	0	GeoreferencedTexture	surface_data	52	2	\N
56	0	0	_TextureParametrization	textureparam	1	1	\N
57	0	0	CityModel	citymodel	49	2	\N
58	0	0	Address	address	2	2	\N
59	0	0	ImplicitGeometry	implicit_geometry	1	1	\N
60	0	0	OuterBuildingCeilingSurface	thematic_surface	29	3	\N
61	0	0	OuterBuildingFloorSurface	thematic_surface	29	3	\N
62	0	0	_AbstractBridge	bridge	20	3	\N
63	0	0	BridgePart	bridge	62	3	\N
64	0	1	Bridge	bridge	62	3	\N
65	0	0	BridgeInstallation	bridge_installation	3	3	\N
66	0	0	IntBridgeInstallation	bridge_installation	3	3	\N
67	0	0	_BridgeBoundarySurface	bridge_thematic_surface	3	3	\N
68	0	0	BridgeCeilingSurface	bridge_thematic_surface	67	3	\N
69	0	0	InteriorBridgeWallSurface	bridge_thematic_surface	67	3	\N
70	0	0	BridgeFloorSurface	bridge_thematic_surface	67	3	\N
71	0	0	BridgeRoofSurface	bridge_thematic_surface	67	3	\N
72	0	0	BridgeWallSurface	bridge_thematic_surface	67	3	\N
73	0	0	BridgeGroundSurface	bridge_thematic_surface	67	3	\N
74	0	0	BridgeClosureSurface	bridge_thematic_surface	67	3	\N
75	0	0	OuterBridgeCeilingSurface	bridge_thematic_surface	67	3	\N
76	0	0	OuterBridgeFloorSurface	bridge_thematic_surface	67	3	\N
77	0	0	_BridgeOpening	bridge_opening	3	3	\N
78	0	0	BridgeWindow	bridge_opening	77	3	\N
79	0	0	BridgeDoor	bridge_opening	77	3	\N
80	0	0	BridgeFurniture	bridge_furniture	3	3	\N
81	0	0	BridgeRoom	bridge_room	3	3	\N
82	0	0	BridgeConstructionElement	bridge_constr_element	3	3	\N
83	0	0	_AbstractTunnel	tunnel	20	3	\N
84	0	0	TunnelPart	tunnel	83	3	\N
85	0	1	Tunnel	tunnel	83	3	\N
86	0	0	TunnelInstallation	tunnel_installation	3	3	\N
87	0	0	IntTunnelInstallation	tunnel_installation	3	3	\N
88	0	0	_TunnelBoundarySurface	tunnel_thematic_surface	3	3	\N
89	0	0	TunnelCeilingSurface	tunnel_thematic_surface	88	3	\N
90	0	0	InteriorTunnelWallSurface	tunnel_thematic_surface	88	3	\N
91	0	0	TunnelFloorSurface	tunnel_thematic_surface	88	3	\N
92	0	0	TunnelRoofSurface	tunnel_thematic_surface	88	3	\N
93	0	0	TunnelWallSurface	tunnel_thematic_surface	88	3	\N
94	0	0	TunnelGroundSurface	tunnel_thematic_surface	88	3	\N
95	0	0	TunnelClosureSurface	tunnel_thematic_surface	88	3	\N
96	0	0	OuterTunnelCeilingSurface	tunnel_thematic_surface	88	3	\N
97	0	0	OuterTunnelFloorSurface	tunnel_thematic_surface	88	3	\N
98	0	0	_TunnelOpening	tunnel_opening	3	3	\N
99	0	0	TunnelWindow	tunnel_opening	98	3	\N
100	0	0	TunnelDoor	tunnel_opening	98	3	\N
101	0	0	TunnelFurniture	tunnel_furniture	3	3	\N
102	0	0	HollowSpace	tunnel_hollow_space	3	3	\N
103	0	0	TexCoordList	textureparam	56	1	\N
104	0	0	TexCoordGen	textureparam	56	1	\N
106	0	0	_BrepGeometry	surface_geometry	0	1	\N
107	0	0	Polygon	surface_geometry	106	1	\N
108	0	0	BrepAggregate	surface_geometry	106	1	\N
109	0	0	TexImage	tex_image	0	0	\N
110	0	0	ExternalReference	external_reference	0	0	\N
111	0	0	GridCoverage	grid_coverage	0	0	\N
112	0	0	_genericAttribute	cityobject_genericattrib	0	0	\N
113	0	0	genericAttributeSet	cityobject_genericattrib	112	0	\N
\.


--
-- TOC entry 5545 (class 0 OID 416339)
-- Dependencies: 234
-- Data for Name: opening; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.opening (id, objectclass_id, address_id, lod3_multi_surface_id, lod4_multi_surface_id, lod3_implicit_rep_id, lod4_implicit_rep_id, lod3_implicit_ref_point, lod4_implicit_ref_point, lod3_implicit_transformation, lod4_implicit_transformation) FROM stdin;
\.


--
-- TOC entry 5546 (class 0 OID 416347)
-- Dependencies: 235
-- Data for Name: opening_to_them_surface; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.opening_to_them_surface (opening_id, thematic_surface_id) FROM stdin;
\.


--
-- TOC entry 5562 (class 0 OID 416453)
-- Dependencies: 251
-- Data for Name: plant_cover; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.plant_cover (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, average_height, average_height_unit, lod1_multi_surface_id, lod2_multi_surface_id, lod3_multi_surface_id, lod4_multi_surface_id, lod1_multi_solid_id, lod2_multi_solid_id, lod3_multi_solid_id, lod4_multi_solid_id) FROM stdin;
\.


--
-- TOC entry 5567 (class 0 OID 416490)
-- Dependencies: 256
-- Data for Name: raster_relief; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.raster_relief (id, objectclass_id, raster_uri, coverage_id) FROM stdin;
\.


--
-- TOC entry 5555 (class 0 OID 416398)
-- Dependencies: 244
-- Data for Name: relief_component; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.relief_component (id, objectclass_id, lod, extent) FROM stdin;
\.


--
-- TOC entry 5556 (class 0 OID 416407)
-- Dependencies: 245
-- Data for Name: relief_feat_to_rel_comp; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.relief_feat_to_rel_comp (relief_component_id, relief_feature_id) FROM stdin;
\.


--
-- TOC entry 5557 (class 0 OID 416412)
-- Dependencies: 246
-- Data for Name: relief_feature; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.relief_feature (id, objectclass_id, lod) FROM stdin;
\.


--
-- TOC entry 5547 (class 0 OID 416352)
-- Dependencies: 236
-- Data for Name: room; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.room (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, building_id, lod4_multi_surface_id, lod4_solid_id) FROM stdin;
\.


--
-- TOC entry 5599 (class 0 OID 417070)
-- Dependencies: 288
-- Data for Name: schema; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.schema (id, is_ade_root, citygml_version, xml_namespace_uri, xml_namespace_prefix, xml_schema_location, xml_schemafile, xml_schemafile_type, ade_id) FROM stdin;
\.


--
-- TOC entry 5601 (class 0 OID 417087)
-- Dependencies: 290
-- Data for Name: schema_referencing; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.schema_referencing (referencing_id, referenced_id) FROM stdin;
\.


--
-- TOC entry 5600 (class 0 OID 417079)
-- Dependencies: 289
-- Data for Name: schema_to_objectclass; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.schema_to_objectclass (schema_id, objectclass_id) FROM stdin;
\.


--
-- TOC entry 5563 (class 0 OID 416461)
-- Dependencies: 252
-- Data for Name: solitary_vegetat_object; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.solitary_vegetat_object (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, species, species_codespace, height, height_unit, trunk_diameter, trunk_diameter_unit, crown_diameter, crown_diameter_unit, lod1_brep_id, lod2_brep_id, lod3_brep_id, lod4_brep_id, lod1_other_geom, lod2_other_geom, lod3_other_geom, lod4_other_geom, lod1_implicit_rep_id, lod2_implicit_rep_id, lod3_implicit_rep_id, lod4_implicit_rep_id, lod1_implicit_ref_point, lod2_implicit_ref_point, lod3_implicit_ref_point, lod4_implicit_ref_point, lod1_implicit_transformation, lod2_implicit_transformation, lod3_implicit_transformation, lod4_implicit_transformation) FROM stdin;
\.


--
-- TOC entry 5591 (class 0 OID 416660)
-- Dependencies: 280
-- Data for Name: surface_data; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.surface_data (id, gmlid, gmlid_codespace, name, name_codespace, description, is_front, objectclass_id, x3d_shininess, x3d_transparency, x3d_ambient_intensity, x3d_specular_color, x3d_diffuse_color, x3d_emissive_color, x3d_is_smooth, tex_image_id, tex_texture_type, tex_wrap_mode, tex_border_color, gt_prefer_worldfile, gt_orientation, gt_reference_point) FROM stdin;
\.


--
-- TOC entry 5589 (class 0 OID 416642)
-- Dependencies: 278
-- Data for Name: surface_geometry; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.surface_geometry (id, gmlid, gmlid_codespace, parent_id, root_id, is_solid, is_composite, is_triangulated, is_xlink, is_reverse, solid_geometry, geometry, implicit_geometry, cityobject_id) FROM stdin;
1	ID_20fbbd01-73bc-4659-a564-bda45cc077b0	\N	\N	1	0	0	0	0	0	\N	\N	\N	2
2	UUID_aa6c9cfd-1e8e-4088-b2ff-78bd9b9d518d	\N	1	1	0	0	0	0	0	\N	01030000A06A0F000001000000040000002F302BD0841E3C41B03BDDFF43BE534166834C3272A16740FC1D8A42771E3C419F8F32FA43BE534166834C3272A16740EEB5A0D7761E3C41FF756EBD43BE534166834C3272A167402F302BD0841E3C41B03BDDFF43BE534166834C3272A16740	\N	2
4	ID_08776d98-5b4e-494c-84c8-ac2979cb7c9b	\N	\N	4	0	0	0	0	0	\N	\N	\N	3
5	UUID_9468be02-259c-4ff5-b092-be2579e5d7cf	\N	4	4	0	0	0	0	0	\N	01030000A06A0F00000100000005000000F3751966741E3C4166BD18AF4DBE53415130630A56F864401E34BBC6731E3C41D105F57B44BE53415130630A56F864401E34BBC6731E3C41D105F57B44BE534166834C3272A16740F3751966741E3C4166BD18AF4DBE534166834C3272A16740F3751966741E3C4166BD18AF4DBE53415130630A56F86440	\N	3
\.


--
-- TOC entry 5595 (class 0 OID 416696)
-- Dependencies: 284
-- Data for Name: tex_image; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.tex_image (id, tex_image_uri, tex_image_data, tex_mime_type, tex_mime_type_codespace) FROM stdin;
\.


--
-- TOC entry 5551 (class 0 OID 416369)
-- Dependencies: 240
-- Data for Name: textureparam; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.textureparam (surface_geometry_id, is_texture_parametrization, world_to_texture, texture_coordinates, surface_data_id) FROM stdin;
\.


--
-- TOC entry 5548 (class 0 OID 416360)
-- Dependencies: 237
-- Data for Name: thematic_surface; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.thematic_surface (id, objectclass_id, building_id, room_id, building_installation_id, lod2_multi_surface_id, lod3_multi_surface_id, lod4_multi_surface_id) FROM stdin;
2	33	1	\N	\N	1	\N	\N
3	34	1	\N	\N	4	\N	\N
\.


--
-- TOC entry 5558 (class 0 OID 416421)
-- Dependencies: 247
-- Data for Name: tin_relief; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.tin_relief (id, objectclass_id, max_length, max_length_unit, stop_lines, break_lines, control_points, surface_geometry_id) FROM stdin;
\.


--
-- TOC entry 5560 (class 0 OID 416437)
-- Dependencies: 249
-- Data for Name: traffic_area; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.traffic_area (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, surface_material, surface_material_codespace, lod2_multi_surface_id, lod3_multi_surface_id, lod4_multi_surface_id, transportation_complex_id) FROM stdin;
\.


--
-- TOC entry 5559 (class 0 OID 416429)
-- Dependencies: 248
-- Data for Name: transportation_complex; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.transportation_complex (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, lod0_network, lod1_multi_surface_id, lod2_multi_surface_id, lod3_multi_surface_id, lod4_multi_surface_id) FROM stdin;
\.


--
-- TOC entry 5568 (class 0 OID 416498)
-- Dependencies: 257
-- Data for Name: tunnel; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.tunnel (id, objectclass_id, tunnel_parent_id, tunnel_root_id, class, class_codespace, function, function_codespace, usage, usage_codespace, year_of_construction, year_of_demolition, lod1_terrain_intersection, lod2_terrain_intersection, lod3_terrain_intersection, lod4_terrain_intersection, lod2_multi_curve, lod3_multi_curve, lod4_multi_curve, lod1_multi_surface_id, lod2_multi_surface_id, lod3_multi_surface_id, lod4_multi_surface_id, lod1_solid_id, lod2_solid_id, lod3_solid_id, lod4_solid_id) FROM stdin;
\.


--
-- TOC entry 5575 (class 0 OID 416542)
-- Dependencies: 264
-- Data for Name: tunnel_furniture; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.tunnel_furniture (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, tunnel_hollow_space_id, lod4_brep_id, lod4_other_geom, lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) FROM stdin;
\.


--
-- TOC entry 5570 (class 0 OID 416511)
-- Dependencies: 259
-- Data for Name: tunnel_hollow_space; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.tunnel_hollow_space (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, tunnel_id, lod4_multi_surface_id, lod4_solid_id) FROM stdin;
\.


--
-- TOC entry 5574 (class 0 OID 416534)
-- Dependencies: 263
-- Data for Name: tunnel_installation; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.tunnel_installation (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, tunnel_id, tunnel_hollow_space_id, lod2_brep_id, lod3_brep_id, lod4_brep_id, lod2_other_geom, lod3_other_geom, lod4_other_geom, lod2_implicit_rep_id, lod3_implicit_rep_id, lod4_implicit_rep_id, lod2_implicit_ref_point, lod3_implicit_ref_point, lod4_implicit_ref_point, lod2_implicit_transformation, lod3_implicit_transformation, lod4_implicit_transformation) FROM stdin;
\.


--
-- TOC entry 5569 (class 0 OID 416506)
-- Dependencies: 258
-- Data for Name: tunnel_open_to_them_srf; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.tunnel_open_to_them_srf (tunnel_opening_id, tunnel_thematic_surface_id) FROM stdin;
\.


--
-- TOC entry 5573 (class 0 OID 416526)
-- Dependencies: 262
-- Data for Name: tunnel_opening; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.tunnel_opening (id, objectclass_id, lod3_multi_surface_id, lod4_multi_surface_id, lod3_implicit_rep_id, lod4_implicit_rep_id, lod3_implicit_ref_point, lod4_implicit_ref_point, lod3_implicit_transformation, lod4_implicit_transformation) FROM stdin;
\.


--
-- TOC entry 5571 (class 0 OID 416519)
-- Dependencies: 260
-- Data for Name: tunnel_thematic_surface; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.tunnel_thematic_surface (id, objectclass_id, tunnel_id, tunnel_hollow_space_id, tunnel_installation_id, lod2_multi_surface_id, lod3_multi_surface_id, lod4_multi_surface_id) FROM stdin;
\.


--
-- TOC entry 5565 (class 0 OID 416477)
-- Dependencies: 254
-- Data for Name: waterbod_to_waterbnd_srf; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.waterbod_to_waterbnd_srf (waterboundary_surface_id, waterbody_id) FROM stdin;
\.


--
-- TOC entry 5564 (class 0 OID 416469)
-- Dependencies: 253
-- Data for Name: waterbody; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.waterbody (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, lod0_multi_curve, lod1_multi_curve, lod0_multi_surface_id, lod1_multi_surface_id, lod1_solid_id, lod2_solid_id, lod3_solid_id, lod4_solid_id) FROM stdin;
\.


--
-- TOC entry 5566 (class 0 OID 416482)
-- Dependencies: 255
-- Data for Name: waterboundary_surface; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

COPY citydb.waterboundary_surface (id, objectclass_id, water_level, water_level_codespace, lod2_surface_id, lod3_surface_id, lod4_surface_id) FROM stdin;
\.


--
-- TOC entry 4571 (class 0 OID 415059)
-- Dependencies: 201
-- Data for Name: spatial_ref_sys; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.spatial_ref_sys (srid, auth_name, auth_srid, srtext, proj4text) FROM stdin;
\.


--
-- TOC entry 5617 (class 0 OID 0)
-- Dependencies: 229
-- Name: address_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.address_seq', 1, false);


--
-- TOC entry 5618 (class 0 OID 0)
-- Dependencies: 287
-- Name: ade_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.ade_seq', 1, false);


--
-- TOC entry 5619 (class 0 OID 0)
-- Dependencies: 238
-- Name: appearance_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.appearance_seq', 1, false);


--
-- TOC entry 5620 (class 0 OID 0)
-- Dependencies: 215
-- Name: citymodel_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.citymodel_seq', 1, false);


--
-- TOC entry 5621 (class 0 OID 0)
-- Dependencies: 227
-- Name: cityobject_genericatt_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.cityobject_genericatt_seq', 1, false);


--
-- TOC entry 5622 (class 0 OID 0)
-- Dependencies: 216
-- Name: cityobject_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.cityobject_seq', 3, true);


--
-- TOC entry 5623 (class 0 OID 0)
-- Dependencies: 218
-- Name: external_ref_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.external_ref_seq', 1, false);


--
-- TOC entry 5624 (class 0 OID 0)
-- Dependencies: 274
-- Name: grid_coverage_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.grid_coverage_seq', 1, false);


--
-- TOC entry 5625 (class 0 OID 0)
-- Dependencies: 225
-- Name: implicit_geometry_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.implicit_geometry_seq', 1, false);


--
-- TOC entry 5626 (class 0 OID 0)
-- Dependencies: 294
-- Name: index_table_id_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.index_table_id_seq', 13, true);


--
-- TOC entry 5627 (class 0 OID 0)
-- Dependencies: 286
-- Name: schema_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.schema_seq', 1, false);


--
-- TOC entry 5628 (class 0 OID 0)
-- Dependencies: 239
-- Name: surface_data_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.surface_data_seq', 1, false);


--
-- TOC entry 5629 (class 0 OID 0)
-- Dependencies: 220
-- Name: surface_geometry_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.surface_geometry_seq', 6, true);


--
-- TOC entry 5630 (class 0 OID 0)
-- Dependencies: 261
-- Name: tex_image_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.tex_image_seq', 1, false);


--
-- TOC entry 5062 (class 2606 OID 416659)
-- Name: address address_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.address
    ADD CONSTRAINT address_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5032 (class 2606 OID 416612)
-- Name: address_to_bridge address_to_bridge_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.address_to_bridge
    ADD CONSTRAINT address_to_bridge_pk PRIMARY KEY (bridge_id, address_id) WITH (fillfactor='100');


--
-- TOC entry 4667 (class 2606 OID 416314)
-- Name: address_to_building address_to_building_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.address_to_building
    ADD CONSTRAINT address_to_building_pk PRIMARY KEY (building_id, address_id) WITH (fillfactor='100');


--
-- TOC entry 5099 (class 2606 OID 417124)
-- Name: ade ade_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.ade
    ADD CONSTRAINT ade_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5101 (class 2606 OID 417133)
-- Name: aggregation_info aggregation_info_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.aggregation_info
    ADD CONSTRAINT aggregation_info_pk PRIMARY KEY (child_id, parent_id, join_table_or_column_name);


--
-- TOC entry 4751 (class 2606 OID 416381)
-- Name: appear_to_surface_data appear_to_surface_data_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.appear_to_surface_data
    ADD CONSTRAINT appear_to_surface_data_pk PRIMARY KEY (surface_data_id, appearance_id) WITH (fillfactor='100');


--
-- TOC entry 5046 (class 2606 OID 416632)
-- Name: appearance appearance_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.appearance
    ADD CONSTRAINT appearance_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4755 (class 2606 OID 416389)
-- Name: breakline_relief breakline_relief_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.breakline_relief
    ADD CONSTRAINT breakline_relief_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5015 (class 2606 OID 416607)
-- Name: bridge_constr_element bridge_constr_element_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_element_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4957 (class 2606 OID 416565)
-- Name: bridge_furniture bridge_furniture_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_furniture
    ADD CONSTRAINT bridge_furniture_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4974 (class 2606 OID 416573)
-- Name: bridge_installation bridge_installation_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_installation_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4988 (class 2606 OID 416586)
-- Name: bridge_open_to_them_srf bridge_open_to_them_srf_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_open_to_them_srf
    ADD CONSTRAINT bridge_open_to_them_srf_pk PRIMARY KEY (bridge_opening_id, bridge_thematic_surface_id) WITH (fillfactor='100');


--
-- TOC entry 4984 (class 2606 OID 416581)
-- Name: bridge_opening bridge_opening_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_opening_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4948 (class 2606 OID 416557)
-- Name: bridge bridge_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4994 (class 2606 OID 416594)
-- Name: bridge_room bridge_room_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_room
    ADD CONSTRAINT bridge_room_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5004 (class 2606 OID 416599)
-- Name: bridge_thematic_surface bridge_thematic_surface_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT bridge_thematic_surface_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4697 (class 2606 OID 416330)
-- Name: building_furniture building_furniture_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_furniture
    ADD CONSTRAINT building_furniture_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4714 (class 2606 OID 416338)
-- Name: building_installation building_installation_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT building_installation_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4688 (class 2606 OID 416322)
-- Name: building building_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4635 (class 2606 OID 416297)
-- Name: city_furniture city_furniture_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furniture_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5073 (class 2606 OID 416677)
-- Name: citymodel citymodel_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.citymodel
    ADD CONSTRAINT citymodel_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5075 (class 2606 OID 416686)
-- Name: cityobject_genericattrib cityobj_genericattrib_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobject_genericattrib
    ADD CONSTRAINT cityobj_genericattrib_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4592 (class 2606 OID 416249)
-- Name: cityobject_member cityobject_member_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobject_member
    ADD CONSTRAINT cityobject_member_pk PRIMARY KEY (citymodel_id, cityobject_id) WITH (fillfactor='100');


--
-- TOC entry 5041 (class 2606 OID 416623)
-- Name: cityobject cityobject_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobject
    ADD CONSTRAINT cityobject_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4598 (class 2606 OID 416266)
-- Name: cityobjectgroup cityobjectgroup_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobjectgroup
    ADD CONSTRAINT cityobjectgroup_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4608 (class 2606 OID 416279)
-- Name: database_srs database_srs_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.database_srs
    ADD CONSTRAINT database_srs_pk PRIMARY KEY (srid) WITH (fillfactor='100');


--
-- TOC entry 5082 (class 2606 OID 416695)
-- Name: external_reference external_reference_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.external_reference
    ADD CONSTRAINT external_reference_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4596 (class 2606 OID 416256)
-- Name: generalization generalization_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generalization
    ADD CONSTRAINT generalization_pk PRIMARY KEY (cityobject_id, generalizes_to_id) WITH (fillfactor='100');


--
-- TOC entry 4663 (class 2606 OID 416307)
-- Name: generic_cityobject generic_cityobject_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT generic_cityobject_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5086 (class 2606 OID 416713)
-- Name: grid_coverage grid_coverage_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.grid_coverage
    ADD CONSTRAINT grid_coverage_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4606 (class 2606 OID 416271)
-- Name: group_to_cityobject group_to_cityobject_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.group_to_cityobject
    ADD CONSTRAINT group_to_cityobject_pk PRIMARY KEY (cityobject_id, cityobjectgroup_id) WITH (fillfactor='100');


--
-- TOC entry 5051 (class 2606 OID 416641)
-- Name: implicit_geometry implicit_geometry_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.implicit_geometry
    ADD CONSTRAINT implicit_geometry_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5103 (class 2606 OID 418804)
-- Name: index_table index_table_pkey; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.index_table
    ADD CONSTRAINT index_table_pkey PRIMARY KEY (id);


--
-- TOC entry 4801 (class 2606 OID 416452)
-- Name: land_use land_use_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4759 (class 2606 OID 416397)
-- Name: masspoint_relief masspoint_relief_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.masspoint_relief
    ADD CONSTRAINT masspoint_relief_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4611 (class 2606 OID 416287)
-- Name: objectclass objectclass_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.objectclass
    ADD CONSTRAINT objectclass_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4724 (class 2606 OID 416346)
-- Name: opening opening_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4728 (class 2606 OID 416351)
-- Name: opening_to_them_surface opening_to_them_surface_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.opening_to_them_surface
    ADD CONSTRAINT opening_to_them_surface_pk PRIMARY KEY (opening_id, thematic_surface_id) WITH (fillfactor='100');


--
-- TOC entry 4812 (class 2606 OID 416460)
-- Name: plant_cover plant_cover_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4856 (class 2606 OID 416497)
-- Name: raster_relief raster_relief_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.raster_relief
    ADD CONSTRAINT raster_relief_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4764 (class 2606 OID 416406)
-- Name: relief_component relief_component_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.relief_component
    ADD CONSTRAINT relief_component_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4768 (class 2606 OID 416411)
-- Name: relief_feat_to_rel_comp relief_feat_to_rel_comp_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.relief_feat_to_rel_comp
    ADD CONSTRAINT relief_feat_to_rel_comp_pk PRIMARY KEY (relief_component_id, relief_feature_id) WITH (fillfactor='100');


--
-- TOC entry 4771 (class 2606 OID 416420)
-- Name: relief_feature relief_feature_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.relief_feature
    ADD CONSTRAINT relief_feature_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4734 (class 2606 OID 416359)
-- Name: room room_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.room
    ADD CONSTRAINT room_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5089 (class 2606 OID 417078)
-- Name: schema schema_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.schema
    ADD CONSTRAINT schema_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5097 (class 2606 OID 417091)
-- Name: schema_referencing schema_referencing_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.schema_referencing
    ADD CONSTRAINT schema_referencing_pk PRIMARY KEY (referenced_id, referencing_id) WITH (fillfactor='100');


--
-- TOC entry 5093 (class 2606 OID 417083)
-- Name: schema_to_objectclass schema_to_objectclass_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.schema_to_objectclass
    ADD CONSTRAINT schema_to_objectclass_pk PRIMARY KEY (schema_id, objectclass_id) WITH (fillfactor='100');


--
-- TOC entry 4831 (class 2606 OID 416468)
-- Name: solitary_vegetat_object solitary_veg_object_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT solitary_veg_object_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5067 (class 2606 OID 416668)
-- Name: surface_data surface_data_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.surface_data
    ADD CONSTRAINT surface_data_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5059 (class 2606 OID 416650)
-- Name: surface_geometry surface_geometry_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.surface_geometry
    ADD CONSTRAINT surface_geometry_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5084 (class 2606 OID 416704)
-- Name: tex_image tex_image_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tex_image
    ADD CONSTRAINT tex_image_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4747 (class 2606 OID 416376)
-- Name: textureparam textureparam_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.textureparam
    ADD CONSTRAINT textureparam_pk PRIMARY KEY (surface_geometry_id, surface_data_id) WITH (fillfactor='100');


--
-- TOC entry 4743 (class 2606 OID 416364)
-- Name: thematic_surface thematic_surface_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT thematic_surface_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4777 (class 2606 OID 416428)
-- Name: tin_relief tin_relief_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tin_relief
    ADD CONSTRAINT tin_relief_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4792 (class 2606 OID 416444)
-- Name: traffic_area traffic_area_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.traffic_area
    ADD CONSTRAINT traffic_area_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4786 (class 2606 OID 416436)
-- Name: transportation_complex transportation_complex_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.transportation_complex
    ADD CONSTRAINT transportation_complex_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4929 (class 2606 OID 416549)
-- Name: tunnel_furniture tunnel_furniture_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_furniture
    ADD CONSTRAINT tunnel_furniture_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4886 (class 2606 OID 416518)
-- Name: tunnel_hollow_space tunnel_hollow_space_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_hollow_space
    ADD CONSTRAINT tunnel_hollow_space_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4921 (class 2606 OID 416541)
-- Name: tunnel_installation tunnel_installation_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_installation_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4880 (class 2606 OID 416510)
-- Name: tunnel_open_to_them_srf tunnel_open_to_them_srf_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_open_to_them_srf
    ADD CONSTRAINT tunnel_open_to_them_srf_pk PRIMARY KEY (tunnel_opening_id, tunnel_thematic_surface_id) WITH (fillfactor='100');


--
-- TOC entry 4904 (class 2606 OID 416533)
-- Name: tunnel_opening tunnel_opening_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_opening
    ADD CONSTRAINT tunnel_opening_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4875 (class 2606 OID 416505)
-- Name: tunnel tunnel_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4895 (class 2606 OID 416523)
-- Name: tunnel_thematic_surface tunnel_thematic_surface_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tunnel_thematic_surface_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4846 (class 2606 OID 416481)
-- Name: waterbod_to_waterbnd_srf waterbod_to_waterbnd_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbod_to_waterbnd_srf
    ADD CONSTRAINT waterbod_to_waterbnd_pk PRIMARY KEY (waterboundary_surface_id, waterbody_id) WITH (fillfactor='100');


--
-- TOC entry 4842 (class 2606 OID 416476)
-- Name: waterbody waterbody_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 4852 (class 2606 OID 416489)
-- Name: waterboundary_surface waterboundary_surface_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterboundary_surface
    ADD CONSTRAINT waterboundary_surface_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5060 (class 1259 OID 417068)
-- Name: address_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX address_inx ON citydb.address USING btree (gmlid, gmlid_codespace);


--
-- TOC entry 5063 (class 1259 OID 420631)
-- Name: address_point_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX address_point_spx ON citydb.address USING gist (multi_point);


--
-- TOC entry 5029 (class 1259 OID 417039)
-- Name: address_to_bridge_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX address_to_bridge_fkx ON citydb.address_to_bridge USING btree (address_id) WITH (fillfactor='90');


--
-- TOC entry 5030 (class 1259 OID 417040)
-- Name: address_to_bridge_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX address_to_bridge_fkx1 ON citydb.address_to_bridge USING btree (bridge_id) WITH (fillfactor='90');


--
-- TOC entry 4664 (class 1259 OID 416773)
-- Name: address_to_building_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX address_to_building_fkx ON citydb.address_to_building USING btree (address_id) WITH (fillfactor='90');


--
-- TOC entry 4665 (class 1259 OID 416774)
-- Name: address_to_building_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX address_to_building_fkx1 ON citydb.address_to_building USING btree (building_id) WITH (fillfactor='90');


--
-- TOC entry 4748 (class 1259 OID 416836)
-- Name: app_to_surf_data_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX app_to_surf_data_fkx ON citydb.appear_to_surface_data USING btree (surface_data_id) WITH (fillfactor='90');


--
-- TOC entry 4749 (class 1259 OID 416837)
-- Name: app_to_surf_data_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX app_to_surf_data_fkx1 ON citydb.appear_to_surface_data USING btree (appearance_id) WITH (fillfactor='90');


--
-- TOC entry 5042 (class 1259 OID 417046)
-- Name: appearance_citymodel_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX appearance_citymodel_fkx ON citydb.appearance USING btree (citymodel_id) WITH (fillfactor='90');


--
-- TOC entry 5043 (class 1259 OID 417047)
-- Name: appearance_cityobject_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX appearance_cityobject_fkx ON citydb.appearance USING btree (cityobject_id) WITH (fillfactor='90');


--
-- TOC entry 5044 (class 1259 OID 417044)
-- Name: appearance_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX appearance_inx ON citydb.appearance USING btree (gmlid, gmlid_codespace) WITH (fillfactor='90');


--
-- TOC entry 5047 (class 1259 OID 417045)
-- Name: appearance_theme_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX appearance_theme_inx ON citydb.appearance USING btree (theme) WITH (fillfactor='90');


--
-- TOC entry 4690 (class 1259 OID 416795)
-- Name: bldg_furn_lod4brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_furn_lod4brep_fkx ON citydb.building_furniture USING btree (lod4_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4691 (class 1259 OID 416797)
-- Name: bldg_furn_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_furn_lod4impl_fkx ON citydb.building_furniture USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4692 (class 1259 OID 421188)
-- Name: bldg_furn_lod4refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_furn_lod4refpt_spx ON citydb.building_furniture USING gist (lod4_implicit_ref_point);


--
-- TOC entry 4693 (class 1259 OID 421175)
-- Name: bldg_furn_lod4xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_furn_lod4xgeom_spx ON citydb.building_furniture USING gist (lod4_other_geom);


--
-- TOC entry 4694 (class 1259 OID 417100)
-- Name: bldg_furn_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_furn_objclass_fkx ON citydb.building_furniture USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4695 (class 1259 OID 416794)
-- Name: bldg_furn_room_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_furn_room_fkx ON citydb.building_furniture USING btree (room_id) WITH (fillfactor='90');


--
-- TOC entry 4698 (class 1259 OID 416800)
-- Name: bldg_inst_building_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_building_fkx ON citydb.building_installation USING btree (building_id) WITH (fillfactor='90');


--
-- TOC entry 4699 (class 1259 OID 416802)
-- Name: bldg_inst_lod2brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod2brep_fkx ON citydb.building_installation USING btree (lod2_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4700 (class 1259 OID 416808)
-- Name: bldg_inst_lod2impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod2impl_fkx ON citydb.building_installation USING btree (lod2_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4701 (class 1259 OID 421118)
-- Name: bldg_inst_lod2refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod2refpt_spx ON citydb.building_installation USING gist (lod2_implicit_ref_point);


--
-- TOC entry 4702 (class 1259 OID 421052)
-- Name: bldg_inst_lod2xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod2xgeom_spx ON citydb.building_installation USING gist (lod2_other_geom);


--
-- TOC entry 4703 (class 1259 OID 416803)
-- Name: bldg_inst_lod3brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod3brep_fkx ON citydb.building_installation USING btree (lod3_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4704 (class 1259 OID 416809)
-- Name: bldg_inst_lod3impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod3impl_fkx ON citydb.building_installation USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4705 (class 1259 OID 421140)
-- Name: bldg_inst_lod3refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod3refpt_spx ON citydb.building_installation USING gist (lod3_implicit_ref_point);


--
-- TOC entry 4706 (class 1259 OID 421074)
-- Name: bldg_inst_lod3xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod3xgeom_spx ON citydb.building_installation USING gist (lod3_other_geom);


--
-- TOC entry 4707 (class 1259 OID 416804)
-- Name: bldg_inst_lod4brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod4brep_fkx ON citydb.building_installation USING btree (lod4_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4708 (class 1259 OID 416810)
-- Name: bldg_inst_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod4impl_fkx ON citydb.building_installation USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4709 (class 1259 OID 421162)
-- Name: bldg_inst_lod4refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod4refpt_spx ON citydb.building_installation USING gist (lod4_implicit_ref_point);


--
-- TOC entry 4710 (class 1259 OID 421096)
-- Name: bldg_inst_lod4xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod4xgeom_spx ON citydb.building_installation USING gist (lod4_other_geom);


--
-- TOC entry 4711 (class 1259 OID 416799)
-- Name: bldg_inst_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_objclass_fkx ON citydb.building_installation USING btree (objectclass_id);


--
-- TOC entry 4712 (class 1259 OID 416801)
-- Name: bldg_inst_room_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_room_fkx ON citydb.building_installation USING btree (room_id) WITH (fillfactor='90');


--
-- TOC entry 4985 (class 1259 OID 417005)
-- Name: brd_open_to_them_srf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX brd_open_to_them_srf_fkx ON citydb.bridge_open_to_them_srf USING btree (bridge_opening_id) WITH (fillfactor='90');


--
-- TOC entry 4986 (class 1259 OID 417006)
-- Name: brd_open_to_them_srf_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX brd_open_to_them_srf_fkx1 ON citydb.bridge_open_to_them_srf USING btree (bridge_thematic_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4995 (class 1259 OID 417014)
-- Name: brd_them_srf_brd_const_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX brd_them_srf_brd_const_fkx ON citydb.bridge_thematic_surface USING btree (bridge_constr_element_id) WITH (fillfactor='90');


--
-- TOC entry 4996 (class 1259 OID 417013)
-- Name: brd_them_srf_brd_inst_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX brd_them_srf_brd_inst_fkx ON citydb.bridge_thematic_surface USING btree (bridge_installation_id) WITH (fillfactor='90');


--
-- TOC entry 4997 (class 1259 OID 417012)
-- Name: brd_them_srf_brd_room_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX brd_them_srf_brd_room_fkx ON citydb.bridge_thematic_surface USING btree (bridge_room_id) WITH (fillfactor='90');


--
-- TOC entry 4998 (class 1259 OID 417011)
-- Name: brd_them_srf_bridge_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX brd_them_srf_bridge_fkx ON citydb.bridge_thematic_surface USING btree (bridge_id) WITH (fillfactor='90');


--
-- TOC entry 4999 (class 1259 OID 417015)
-- Name: brd_them_srf_lod2msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX brd_them_srf_lod2msrf_fkx ON citydb.bridge_thematic_surface USING btree (lod2_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5000 (class 1259 OID 417016)
-- Name: brd_them_srf_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX brd_them_srf_lod3msrf_fkx ON citydb.bridge_thematic_surface USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5001 (class 1259 OID 417017)
-- Name: brd_them_srf_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX brd_them_srf_lod4msrf_fkx ON citydb.bridge_thematic_surface USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5002 (class 1259 OID 417010)
-- Name: brd_them_srf_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX brd_them_srf_objclass_fkx ON citydb.bridge_thematic_surface USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4752 (class 1259 OID 421217)
-- Name: breakline_break_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX breakline_break_spx ON citydb.breakline_relief USING gist (break_lines);


--
-- TOC entry 4753 (class 1259 OID 417094)
-- Name: breakline_rel_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX breakline_rel_objclass_fkx ON citydb.breakline_relief USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4756 (class 1259 OID 421207)
-- Name: breakline_ridge_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX breakline_ridge_spx ON citydb.breakline_relief USING gist (ridge_or_valley_lines);


--
-- TOC entry 5005 (class 1259 OID 420394)
-- Name: bridge_const_lod1refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_const_lod1refpt_spx ON citydb.bridge_constr_element USING gist (lod1_implicit_ref_point);


--
-- TOC entry 5006 (class 1259 OID 420278)
-- Name: bridge_const_lod1xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_const_lod1xgeom_spx ON citydb.bridge_constr_element USING gist (lod1_other_geom);


--
-- TOC entry 5007 (class 1259 OID 420423)
-- Name: bridge_const_lod2refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_const_lod2refpt_spx ON citydb.bridge_constr_element USING gist (lod2_implicit_ref_point);


--
-- TOC entry 5008 (class 1259 OID 420307)
-- Name: bridge_const_lod2xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_const_lod2xgeom_spx ON citydb.bridge_constr_element USING gist (lod2_other_geom);


--
-- TOC entry 5009 (class 1259 OID 420452)
-- Name: bridge_const_lod3refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_const_lod3refpt_spx ON citydb.bridge_constr_element USING gist (lod3_implicit_ref_point);


--
-- TOC entry 5010 (class 1259 OID 420336)
-- Name: bridge_const_lod3xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_const_lod3xgeom_spx ON citydb.bridge_constr_element USING gist (lod3_other_geom);


--
-- TOC entry 5011 (class 1259 OID 420481)
-- Name: bridge_const_lod4refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_const_lod4refpt_spx ON citydb.bridge_constr_element USING gist (lod4_implicit_ref_point);


--
-- TOC entry 5012 (class 1259 OID 420365)
-- Name: bridge_const_lod4xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_const_lod4xgeom_spx ON citydb.bridge_constr_element USING gist (lod4_other_geom);


--
-- TOC entry 5013 (class 1259 OID 417018)
-- Name: bridge_constr_bridge_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_bridge_fkx ON citydb.bridge_constr_element USING btree (bridge_id) WITH (fillfactor='90');


--
-- TOC entry 5016 (class 1259 OID 417023)
-- Name: bridge_constr_lod1brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod1brep_fkx ON citydb.bridge_constr_element USING btree (lod1_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5017 (class 1259 OID 417031)
-- Name: bridge_constr_lod1impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod1impl_fkx ON citydb.bridge_constr_element USING btree (lod1_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5018 (class 1259 OID 420162)
-- Name: bridge_constr_lod1terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod1terr_spx ON citydb.bridge_constr_element USING gist (lod1_terrain_intersection);


--
-- TOC entry 5019 (class 1259 OID 417024)
-- Name: bridge_constr_lod2brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod2brep_fkx ON citydb.bridge_constr_element USING btree (lod2_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5020 (class 1259 OID 417032)
-- Name: bridge_constr_lod2impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod2impl_fkx ON citydb.bridge_constr_element USING btree (lod2_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5021 (class 1259 OID 420191)
-- Name: bridge_constr_lod2terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod2terr_spx ON citydb.bridge_constr_element USING gist (lod2_terrain_intersection);


--
-- TOC entry 5022 (class 1259 OID 417025)
-- Name: bridge_constr_lod3brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod3brep_fkx ON citydb.bridge_constr_element USING btree (lod3_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5023 (class 1259 OID 417033)
-- Name: bridge_constr_lod3impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod3impl_fkx ON citydb.bridge_constr_element USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5024 (class 1259 OID 420220)
-- Name: bridge_constr_lod3terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod3terr_spx ON citydb.bridge_constr_element USING gist (lod3_terrain_intersection);


--
-- TOC entry 5025 (class 1259 OID 417026)
-- Name: bridge_constr_lod4brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod4brep_fkx ON citydb.bridge_constr_element USING btree (lod4_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5026 (class 1259 OID 417034)
-- Name: bridge_constr_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod4impl_fkx ON citydb.bridge_constr_element USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5027 (class 1259 OID 420249)
-- Name: bridge_constr_lod4terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod4terr_spx ON citydb.bridge_constr_element USING gist (lod4_terrain_intersection);


--
-- TOC entry 5028 (class 1259 OID 417096)
-- Name: bridge_constr_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_objclass_fkx ON citydb.bridge_constr_element USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4950 (class 1259 OID 416977)
-- Name: bridge_furn_brd_room_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_furn_brd_room_fkx ON citydb.bridge_furniture USING btree (bridge_room_id) WITH (fillfactor='90');


--
-- TOC entry 4951 (class 1259 OID 416978)
-- Name: bridge_furn_lod4brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_furn_lod4brep_fkx ON citydb.bridge_furniture USING btree (lod4_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4952 (class 1259 OID 416980)
-- Name: bridge_furn_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_furn_lod4impl_fkx ON citydb.bridge_furniture USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4953 (class 1259 OID 421243)
-- Name: bridge_furn_lod4refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_furn_lod4refpt_spx ON citydb.bridge_furniture USING gist (lod4_implicit_ref_point);


--
-- TOC entry 4954 (class 1259 OID 421230)
-- Name: bridge_furn_lod4xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_furn_lod4xgeom_spx ON citydb.bridge_furniture USING gist (lod4_other_geom);


--
-- TOC entry 4955 (class 1259 OID 417097)
-- Name: bridge_furn_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_furn_objclass_fkx ON citydb.bridge_furniture USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4958 (class 1259 OID 416984)
-- Name: bridge_inst_brd_room_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_brd_room_fkx ON citydb.bridge_installation USING btree (bridge_room_id) WITH (fillfactor='90');


--
-- TOC entry 4959 (class 1259 OID 416983)
-- Name: bridge_inst_bridge_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_bridge_fkx ON citydb.bridge_installation USING btree (bridge_id) WITH (fillfactor='90');


--
-- TOC entry 4960 (class 1259 OID 416985)
-- Name: bridge_inst_lod2brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod2brep_fkx ON citydb.bridge_installation USING btree (lod2_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4961 (class 1259 OID 416991)
-- Name: bridge_inst_lod2impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod2impl_fkx ON citydb.bridge_installation USING btree (lod2_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4962 (class 1259 OID 420059)
-- Name: bridge_inst_lod2refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod2refpt_spx ON citydb.bridge_installation USING gist (lod2_implicit_ref_point);


--
-- TOC entry 4963 (class 1259 OID 419993)
-- Name: bridge_inst_lod2xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod2xgeom_spx ON citydb.bridge_installation USING gist (lod2_other_geom);


--
-- TOC entry 4964 (class 1259 OID 416986)
-- Name: bridge_inst_lod3brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod3brep_fkx ON citydb.bridge_installation USING btree (lod3_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4965 (class 1259 OID 416992)
-- Name: bridge_inst_lod3impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod3impl_fkx ON citydb.bridge_installation USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4966 (class 1259 OID 420081)
-- Name: bridge_inst_lod3refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod3refpt_spx ON citydb.bridge_installation USING gist (lod3_implicit_ref_point);


--
-- TOC entry 4967 (class 1259 OID 420015)
-- Name: bridge_inst_lod3xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod3xgeom_spx ON citydb.bridge_installation USING gist (lod3_other_geom);


--
-- TOC entry 4968 (class 1259 OID 416987)
-- Name: bridge_inst_lod4brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod4brep_fkx ON citydb.bridge_installation USING btree (lod4_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4969 (class 1259 OID 416993)
-- Name: bridge_inst_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod4impl_fkx ON citydb.bridge_installation USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4970 (class 1259 OID 420103)
-- Name: bridge_inst_lod4refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod4refpt_spx ON citydb.bridge_installation USING gist (lod4_implicit_ref_point);


--
-- TOC entry 4971 (class 1259 OID 420037)
-- Name: bridge_inst_lod4xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod4xgeom_spx ON citydb.bridge_installation USING gist (lod4_other_geom);


--
-- TOC entry 4972 (class 1259 OID 416982)
-- Name: bridge_inst_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_objclass_fkx ON citydb.bridge_installation USING btree (objectclass_id);


--
-- TOC entry 4930 (class 1259 OID 416969)
-- Name: bridge_lod1msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod1msrf_fkx ON citydb.bridge USING btree (lod1_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4931 (class 1259 OID 416973)
-- Name: bridge_lod1solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod1solid_fkx ON citydb.bridge USING btree (lod1_solid_id) WITH (fillfactor='90');


--
-- TOC entry 4932 (class 1259 OID 421336)
-- Name: bridge_lod1terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod1terr_spx ON citydb.bridge USING gist (lod1_terrain_intersection);


--
-- TOC entry 4933 (class 1259 OID 421436)
-- Name: bridge_lod2curve_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod2curve_spx ON citydb.bridge USING gist (lod2_multi_curve);


--
-- TOC entry 4934 (class 1259 OID 416970)
-- Name: bridge_lod2msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod2msrf_fkx ON citydb.bridge USING btree (lod2_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4935 (class 1259 OID 416974)
-- Name: bridge_lod2solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod2solid_fkx ON citydb.bridge USING btree (lod2_solid_id) WITH (fillfactor='90');


--
-- TOC entry 4936 (class 1259 OID 421361)
-- Name: bridge_lod2terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod2terr_spx ON citydb.bridge USING gist (lod2_terrain_intersection);


--
-- TOC entry 4937 (class 1259 OID 421461)
-- Name: bridge_lod3curve_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod3curve_spx ON citydb.bridge USING gist (lod3_multi_curve);


--
-- TOC entry 4938 (class 1259 OID 416971)
-- Name: bridge_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod3msrf_fkx ON citydb.bridge USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4939 (class 1259 OID 416975)
-- Name: bridge_lod3solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod3solid_fkx ON citydb.bridge USING btree (lod3_solid_id) WITH (fillfactor='90');


--
-- TOC entry 4940 (class 1259 OID 421386)
-- Name: bridge_lod3terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod3terr_spx ON citydb.bridge USING gist (lod3_terrain_intersection);


--
-- TOC entry 4941 (class 1259 OID 421486)
-- Name: bridge_lod4curve_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod4curve_spx ON citydb.bridge USING gist (lod4_multi_curve);


--
-- TOC entry 4942 (class 1259 OID 416972)
-- Name: bridge_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod4msrf_fkx ON citydb.bridge USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4943 (class 1259 OID 416976)
-- Name: bridge_lod4solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod4solid_fkx ON citydb.bridge USING btree (lod4_solid_id) WITH (fillfactor='90');


--
-- TOC entry 4944 (class 1259 OID 421411)
-- Name: bridge_lod4terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod4terr_spx ON citydb.bridge USING gist (lod4_terrain_intersection);


--
-- TOC entry 4945 (class 1259 OID 417095)
-- Name: bridge_objectclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_objectclass_fkx ON citydb.bridge USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4975 (class 1259 OID 416998)
-- Name: bridge_open_address_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_open_address_fkx ON citydb.bridge_opening USING btree (address_id) WITH (fillfactor='90');


--
-- TOC entry 4976 (class 1259 OID 417001)
-- Name: bridge_open_lod3impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_open_lod3impl_fkx ON citydb.bridge_opening USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4977 (class 1259 OID 416999)
-- Name: bridge_open_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_open_lod3msrf_fkx ON citydb.bridge_opening USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4978 (class 1259 OID 420118)
-- Name: bridge_open_lod3refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_open_lod3refpt_spx ON citydb.bridge_opening USING gist (lod3_implicit_ref_point);


--
-- TOC entry 4979 (class 1259 OID 417002)
-- Name: bridge_open_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_open_lod4impl_fkx ON citydb.bridge_opening USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4980 (class 1259 OID 417000)
-- Name: bridge_open_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_open_lod4msrf_fkx ON citydb.bridge_opening USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4981 (class 1259 OID 420133)
-- Name: bridge_open_lod4refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_open_lod4refpt_spx ON citydb.bridge_opening USING gist (lod4_implicit_ref_point);


--
-- TOC entry 4982 (class 1259 OID 416997)
-- Name: bridge_open_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_open_objclass_fkx ON citydb.bridge_opening USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4946 (class 1259 OID 416960)
-- Name: bridge_parent_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_parent_fkx ON citydb.bridge USING btree (bridge_parent_id) WITH (fillfactor='90');


--
-- TOC entry 4989 (class 1259 OID 417007)
-- Name: bridge_room_bridge_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_room_bridge_fkx ON citydb.bridge_room USING btree (bridge_id) WITH (fillfactor='90');


--
-- TOC entry 4990 (class 1259 OID 417008)
-- Name: bridge_room_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_room_lod4msrf_fkx ON citydb.bridge_room USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4991 (class 1259 OID 417009)
-- Name: bridge_room_lod4solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_room_lod4solid_fkx ON citydb.bridge_room USING btree (lod4_solid_id) WITH (fillfactor='90');


--
-- TOC entry 4992 (class 1259 OID 417098)
-- Name: bridge_room_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_room_objclass_fkx ON citydb.bridge_room USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4949 (class 1259 OID 416961)
-- Name: bridge_root_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_root_fkx ON citydb.bridge USING btree (bridge_root_id) WITH (fillfactor='90');


--
-- TOC entry 4668 (class 1259 OID 416784)
-- Name: building_lod0footprint_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod0footprint_fkx ON citydb.building USING btree (lod0_footprint_id) WITH (fillfactor='90');


--
-- TOC entry 4669 (class 1259 OID 416785)
-- Name: building_lod0roofprint_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod0roofprint_fkx ON citydb.building USING btree (lod0_roofprint_id) WITH (fillfactor='90');


--
-- TOC entry 4670 (class 1259 OID 416786)
-- Name: building_lod1msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod1msrf_fkx ON citydb.building USING btree (lod1_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4671 (class 1259 OID 416790)
-- Name: building_lod1solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod1solid_fkx ON citydb.building USING btree (lod1_solid_id) WITH (fillfactor='90');


--
-- TOC entry 4672 (class 1259 OID 420868)
-- Name: building_lod1terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod1terr_spx ON citydb.building USING gist (lod1_terrain_intersection);


--
-- TOC entry 4673 (class 1259 OID 420976)
-- Name: building_lod2curve_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod2curve_spx ON citydb.building USING gist (lod2_multi_curve);


--
-- TOC entry 4674 (class 1259 OID 416787)
-- Name: building_lod2msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod2msrf_fkx ON citydb.building USING btree (lod2_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4675 (class 1259 OID 416791)
-- Name: building_lod2solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod2solid_fkx ON citydb.building USING btree (lod2_solid_id) WITH (fillfactor='90');


--
-- TOC entry 4676 (class 1259 OID 420895)
-- Name: building_lod2terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod2terr_spx ON citydb.building USING gist (lod2_terrain_intersection);


--
-- TOC entry 4677 (class 1259 OID 421003)
-- Name: building_lod3curve_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod3curve_spx ON citydb.building USING gist (lod3_multi_curve);


--
-- TOC entry 4678 (class 1259 OID 416788)
-- Name: building_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod3msrf_fkx ON citydb.building USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4679 (class 1259 OID 416792)
-- Name: building_lod3solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod3solid_fkx ON citydb.building USING btree (lod3_solid_id) WITH (fillfactor='90');


--
-- TOC entry 4680 (class 1259 OID 420922)
-- Name: building_lod3terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod3terr_spx ON citydb.building USING gist (lod3_terrain_intersection);


--
-- TOC entry 4681 (class 1259 OID 421030)
-- Name: building_lod4curve_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod4curve_spx ON citydb.building USING gist (lod4_multi_curve);


--
-- TOC entry 4682 (class 1259 OID 416789)
-- Name: building_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod4msrf_fkx ON citydb.building USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4683 (class 1259 OID 416793)
-- Name: building_lod4solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod4solid_fkx ON citydb.building USING btree (lod4_solid_id) WITH (fillfactor='90');


--
-- TOC entry 4684 (class 1259 OID 420949)
-- Name: building_lod4terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod4terr_spx ON citydb.building USING gist (lod4_terrain_intersection);


--
-- TOC entry 4685 (class 1259 OID 417099)
-- Name: building_objectclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_objectclass_fkx ON citydb.building USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4686 (class 1259 OID 416775)
-- Name: building_parent_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_parent_fkx ON citydb.building USING btree (building_parent_id) WITH (fillfactor='90');


--
-- TOC entry 4689 (class 1259 OID 416776)
-- Name: building_root_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_root_fkx ON citydb.building USING btree (building_root_id) WITH (fillfactor='90');


--
-- TOC entry 4613 (class 1259 OID 416732)
-- Name: city_furn_lod1brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod1brep_fkx ON citydb.city_furniture USING btree (lod1_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4614 (class 1259 OID 416740)
-- Name: city_furn_lod1impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod1impl_fkx ON citydb.city_furniture USING btree (lod1_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4615 (class 1259 OID 419112)
-- Name: city_furn_lod1refpnt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod1refpnt_spx ON citydb.city_furniture USING gist (lod1_implicit_ref_point);


--
-- TOC entry 4616 (class 1259 OID 418888)
-- Name: city_furn_lod1terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod1terr_spx ON citydb.city_furniture USING gist (lod1_terrain_intersection);


--
-- TOC entry 4617 (class 1259 OID 419000)
-- Name: city_furn_lod1xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod1xgeom_spx ON citydb.city_furniture USING gist (lod1_other_geom);


--
-- TOC entry 4618 (class 1259 OID 416733)
-- Name: city_furn_lod2brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod2brep_fkx ON citydb.city_furniture USING btree (lod2_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4619 (class 1259 OID 416741)
-- Name: city_furn_lod2impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod2impl_fkx ON citydb.city_furniture USING btree (lod2_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4620 (class 1259 OID 419140)
-- Name: city_furn_lod2refpnt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod2refpnt_spx ON citydb.city_furniture USING gist (lod2_implicit_ref_point);


--
-- TOC entry 4621 (class 1259 OID 418916)
-- Name: city_furn_lod2terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod2terr_spx ON citydb.city_furniture USING gist (lod2_terrain_intersection);


--
-- TOC entry 4622 (class 1259 OID 419028)
-- Name: city_furn_lod2xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod2xgeom_spx ON citydb.city_furniture USING gist (lod2_other_geom);


--
-- TOC entry 4623 (class 1259 OID 416734)
-- Name: city_furn_lod3brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod3brep_fkx ON citydb.city_furniture USING btree (lod3_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4624 (class 1259 OID 416742)
-- Name: city_furn_lod3impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod3impl_fkx ON citydb.city_furniture USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4625 (class 1259 OID 419168)
-- Name: city_furn_lod3refpnt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod3refpnt_spx ON citydb.city_furniture USING gist (lod3_implicit_ref_point);


--
-- TOC entry 4626 (class 1259 OID 418944)
-- Name: city_furn_lod3terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod3terr_spx ON citydb.city_furniture USING gist (lod3_terrain_intersection);


--
-- TOC entry 4627 (class 1259 OID 419056)
-- Name: city_furn_lod3xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod3xgeom_spx ON citydb.city_furniture USING gist (lod3_other_geom);


--
-- TOC entry 4628 (class 1259 OID 416735)
-- Name: city_furn_lod4brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod4brep_fkx ON citydb.city_furniture USING btree (lod4_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4629 (class 1259 OID 416743)
-- Name: city_furn_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod4impl_fkx ON citydb.city_furniture USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4630 (class 1259 OID 419196)
-- Name: city_furn_lod4refpnt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod4refpnt_spx ON citydb.city_furniture USING gist (lod4_implicit_ref_point);


--
-- TOC entry 4631 (class 1259 OID 418972)
-- Name: city_furn_lod4terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod4terr_spx ON citydb.city_furniture USING gist (lod4_terrain_intersection);


--
-- TOC entry 4632 (class 1259 OID 419084)
-- Name: city_furn_lod4xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod4xgeom_spx ON citydb.city_furniture USING gist (lod4_other_geom);


--
-- TOC entry 4633 (class 1259 OID 417101)
-- Name: city_furn_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_objclass_fkx ON citydb.city_furniture USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5070 (class 1259 OID 420622)
-- Name: citymodel_envelope_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX citymodel_envelope_spx ON citydb.citymodel USING gist (envelope);


--
-- TOC entry 5071 (class 1259 OID 417059)
-- Name: citymodel_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX citymodel_inx ON citydb.citymodel USING btree (gmlid, gmlid_codespace);


--
-- TOC entry 5033 (class 1259 OID 417134)
-- Name: cityobj_creation_date_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX cityobj_creation_date_inx ON citydb.cityobject USING btree (creation_date) WITH (fillfactor='90');


--
-- TOC entry 5034 (class 1259 OID 417136)
-- Name: cityobj_last_mod_date_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX cityobj_last_mod_date_inx ON citydb.cityobject USING btree (last_modification_date) WITH (fillfactor='90');


--
-- TOC entry 5035 (class 1259 OID 417135)
-- Name: cityobj_term_date_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX cityobj_term_date_inx ON citydb.cityobject USING btree (termination_date) WITH (fillfactor='90');


--
-- TOC entry 5036 (class 1259 OID 421311)
-- Name: cityobject_envelope_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX cityobject_envelope_spx ON citydb.cityobject USING gist (envelope);


--
-- TOC entry 5037 (class 1259 OID 417041)
-- Name: cityobject_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX cityobject_inx ON citydb.cityobject USING btree (gmlid, gmlid_codespace) WITH (fillfactor='90');


--
-- TOC entry 5038 (class 1259 OID 417066)
-- Name: cityobject_lineage_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX cityobject_lineage_inx ON citydb.cityobject USING btree (lineage);


--
-- TOC entry 4589 (class 1259 OID 416718)
-- Name: cityobject_member_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX cityobject_member_fkx ON citydb.cityobject_member USING btree (cityobject_id) WITH (fillfactor='90');


--
-- TOC entry 4590 (class 1259 OID 416719)
-- Name: cityobject_member_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX cityobject_member_fkx1 ON citydb.cityobject_member USING btree (citymodel_id) WITH (fillfactor='90');


--
-- TOC entry 5039 (class 1259 OID 417042)
-- Name: cityobject_objectclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX cityobject_objectclass_fkx ON citydb.cityobject USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5080 (class 1259 OID 417064)
-- Name: ext_ref_cityobject_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX ext_ref_cityobject_fkx ON citydb.external_reference USING btree (cityobject_id) WITH (fillfactor='90');


--
-- TOC entry 4636 (class 1259 OID 416753)
-- Name: gen_object_lod0brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod0brep_fkx ON citydb.generic_cityobject USING btree (lod0_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4637 (class 1259 OID 416763)
-- Name: gen_object_lod0impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod0impl_fkx ON citydb.generic_cityobject USING btree (lod0_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4638 (class 1259 OID 419559)
-- Name: gen_object_lod0refpnt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod0refpnt_spx ON citydb.generic_cityobject USING gist (lod0_implicit_ref_point);


--
-- TOC entry 4639 (class 1259 OID 419229)
-- Name: gen_object_lod0terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod0terr_spx ON citydb.generic_cityobject USING gist (lod0_terrain_intersection);


--
-- TOC entry 4640 (class 1259 OID 419394)
-- Name: gen_object_lod0xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod0xgeom_spx ON citydb.generic_cityobject USING gist (lod0_other_geom);


--
-- TOC entry 4641 (class 1259 OID 416754)
-- Name: gen_object_lod1brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod1brep_fkx ON citydb.generic_cityobject USING btree (lod1_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4642 (class 1259 OID 416764)
-- Name: gen_object_lod1impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod1impl_fkx ON citydb.generic_cityobject USING btree (lod1_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4643 (class 1259 OID 419592)
-- Name: gen_object_lod1refpnt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod1refpnt_spx ON citydb.generic_cityobject USING gist (lod1_implicit_ref_point);


--
-- TOC entry 4644 (class 1259 OID 419262)
-- Name: gen_object_lod1terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod1terr_spx ON citydb.generic_cityobject USING gist (lod1_terrain_intersection);


--
-- TOC entry 4645 (class 1259 OID 419427)
-- Name: gen_object_lod1xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod1xgeom_spx ON citydb.generic_cityobject USING gist (lod1_other_geom);


--
-- TOC entry 4646 (class 1259 OID 416755)
-- Name: gen_object_lod2brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod2brep_fkx ON citydb.generic_cityobject USING btree (lod2_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4647 (class 1259 OID 416765)
-- Name: gen_object_lod2impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod2impl_fkx ON citydb.generic_cityobject USING btree (lod2_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4648 (class 1259 OID 419625)
-- Name: gen_object_lod2refpnt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod2refpnt_spx ON citydb.generic_cityobject USING gist (lod2_implicit_ref_point);


--
-- TOC entry 4649 (class 1259 OID 419295)
-- Name: gen_object_lod2terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod2terr_spx ON citydb.generic_cityobject USING gist (lod2_terrain_intersection);


--
-- TOC entry 4650 (class 1259 OID 419460)
-- Name: gen_object_lod2xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod2xgeom_spx ON citydb.generic_cityobject USING gist (lod2_other_geom);


--
-- TOC entry 4651 (class 1259 OID 416756)
-- Name: gen_object_lod3brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod3brep_fkx ON citydb.generic_cityobject USING btree (lod3_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4652 (class 1259 OID 416766)
-- Name: gen_object_lod3impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod3impl_fkx ON citydb.generic_cityobject USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4653 (class 1259 OID 419658)
-- Name: gen_object_lod3refpnt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod3refpnt_spx ON citydb.generic_cityobject USING gist (lod3_implicit_ref_point);


--
-- TOC entry 4654 (class 1259 OID 419328)
-- Name: gen_object_lod3terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod3terr_spx ON citydb.generic_cityobject USING gist (lod3_terrain_intersection);


--
-- TOC entry 4655 (class 1259 OID 419493)
-- Name: gen_object_lod3xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod3xgeom_spx ON citydb.generic_cityobject USING gist (lod3_other_geom);


--
-- TOC entry 4656 (class 1259 OID 416757)
-- Name: gen_object_lod4brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod4brep_fkx ON citydb.generic_cityobject USING btree (lod4_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4657 (class 1259 OID 416767)
-- Name: gen_object_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod4impl_fkx ON citydb.generic_cityobject USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4658 (class 1259 OID 419691)
-- Name: gen_object_lod4refpnt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod4refpnt_spx ON citydb.generic_cityobject USING gist (lod4_implicit_ref_point);


--
-- TOC entry 4659 (class 1259 OID 419361)
-- Name: gen_object_lod4terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod4terr_spx ON citydb.generic_cityobject USING gist (lod4_terrain_intersection);


--
-- TOC entry 4660 (class 1259 OID 419526)
-- Name: gen_object_lod4xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod4xgeom_spx ON citydb.generic_cityobject USING gist (lod4_other_geom);


--
-- TOC entry 4661 (class 1259 OID 417103)
-- Name: gen_object_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_objclass_fkx ON citydb.generic_cityobject USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4593 (class 1259 OID 416720)
-- Name: general_cityobject_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX general_cityobject_fkx ON citydb.generalization USING btree (cityobject_id) WITH (fillfactor='90');


--
-- TOC entry 4594 (class 1259 OID 416721)
-- Name: general_generalizes_to_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX general_generalizes_to_fkx ON citydb.generalization USING btree (generalizes_to_id) WITH (fillfactor='90');


--
-- TOC entry 5076 (class 1259 OID 417063)
-- Name: genericattrib_cityobj_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX genericattrib_cityobj_fkx ON citydb.cityobject_genericattrib USING btree (cityobject_id) WITH (fillfactor='90');


--
-- TOC entry 5077 (class 1259 OID 417062)
-- Name: genericattrib_geom_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX genericattrib_geom_fkx ON citydb.cityobject_genericattrib USING btree (surface_geometry_id) WITH (fillfactor='90');


--
-- TOC entry 5078 (class 1259 OID 417060)
-- Name: genericattrib_parent_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX genericattrib_parent_fkx ON citydb.cityobject_genericattrib USING btree (parent_genattrib_id) WITH (fillfactor='90');


--
-- TOC entry 5079 (class 1259 OID 417061)
-- Name: genericattrib_root_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX genericattrib_root_fkx ON citydb.cityobject_genericattrib USING btree (root_genattrib_id) WITH (fillfactor='90');


--
-- TOC entry 5087 (class 1259 OID 417065)
-- Name: grid_coverage_raster_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX grid_coverage_raster_spx ON citydb.grid_coverage USING gist (public.st_convexhull(rasterproperty));


--
-- TOC entry 4599 (class 1259 OID 416722)
-- Name: group_brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX group_brep_fkx ON citydb.cityobjectgroup USING btree (brep_id) WITH (fillfactor='90');


--
-- TOC entry 4600 (class 1259 OID 417102)
-- Name: group_objectclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX group_objectclass_fkx ON citydb.cityobjectgroup USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4601 (class 1259 OID 416724)
-- Name: group_parent_cityobj_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX group_parent_cityobj_fkx ON citydb.cityobjectgroup USING btree (parent_cityobject_id) WITH (fillfactor='90');


--
-- TOC entry 4603 (class 1259 OID 416725)
-- Name: group_to_cityobject_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX group_to_cityobject_fkx ON citydb.group_to_cityobject USING btree (cityobject_id) WITH (fillfactor='90');


--
-- TOC entry 4604 (class 1259 OID 416726)
-- Name: group_to_cityobject_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX group_to_cityobject_fkx1 ON citydb.group_to_cityobject USING btree (cityobjectgroup_id) WITH (fillfactor='90');


--
-- TOC entry 4602 (class 1259 OID 418860)
-- Name: group_xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX group_xgeom_spx ON citydb.cityobjectgroup USING gist (other_geom);


--
-- TOC entry 5048 (class 1259 OID 417049)
-- Name: implicit_geom_brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX implicit_geom_brep_fkx ON citydb.implicit_geometry USING btree (relative_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5049 (class 1259 OID 417048)
-- Name: implicit_geom_ref2lib_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX implicit_geom_ref2lib_inx ON citydb.implicit_geometry USING btree (reference_to_library) WITH (fillfactor='90');


--
-- TOC entry 4794 (class 1259 OID 416860)
-- Name: land_use_lod0msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX land_use_lod0msrf_fkx ON citydb.land_use USING btree (lod0_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4795 (class 1259 OID 416861)
-- Name: land_use_lod1msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX land_use_lod1msrf_fkx ON citydb.land_use USING btree (lod1_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4796 (class 1259 OID 416862)
-- Name: land_use_lod2msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX land_use_lod2msrf_fkx ON citydb.land_use USING btree (lod2_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4797 (class 1259 OID 416863)
-- Name: land_use_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX land_use_lod3msrf_fkx ON citydb.land_use USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4798 (class 1259 OID 416864)
-- Name: land_use_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX land_use_lod4msrf_fkx ON citydb.land_use USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4799 (class 1259 OID 417104)
-- Name: land_use_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX land_use_objclass_fkx ON citydb.land_use USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4757 (class 1259 OID 417105)
-- Name: masspoint_rel_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX masspoint_rel_objclass_fkx ON citydb.masspoint_relief USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4760 (class 1259 OID 418813)
-- Name: masspoint_relief_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX masspoint_relief_spx ON citydb.masspoint_relief USING gist (relief_points);


--
-- TOC entry 4609 (class 1259 OID 417086)
-- Name: objectclass_baseclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX objectclass_baseclass_fkx ON citydb.objectclass USING btree (baseclass_id) WITH (fillfactor='90');


--
-- TOC entry 4612 (class 1259 OID 416727)
-- Name: objectclass_superclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX objectclass_superclass_fkx ON citydb.objectclass USING btree (superclass_id) WITH (fillfactor='90');


--
-- TOC entry 4725 (class 1259 OID 416822)
-- Name: open_to_them_surface_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX open_to_them_surface_fkx ON citydb.opening_to_them_surface USING btree (opening_id) WITH (fillfactor='90');


--
-- TOC entry 4726 (class 1259 OID 416823)
-- Name: open_to_them_surface_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX open_to_them_surface_fkx1 ON citydb.opening_to_them_surface USING btree (thematic_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4715 (class 1259 OID 416815)
-- Name: opening_address_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX opening_address_fkx ON citydb.opening USING btree (address_id) WITH (fillfactor='90');


--
-- TOC entry 4716 (class 1259 OID 416818)
-- Name: opening_lod3impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX opening_lod3impl_fkx ON citydb.opening USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4717 (class 1259 OID 416816)
-- Name: opening_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX opening_lod3msrf_fkx ON citydb.opening USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4718 (class 1259 OID 419706)
-- Name: opening_lod3refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX opening_lod3refpt_spx ON citydb.opening USING gist (lod3_implicit_ref_point);


--
-- TOC entry 4719 (class 1259 OID 416819)
-- Name: opening_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX opening_lod4impl_fkx ON citydb.opening USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4720 (class 1259 OID 416817)
-- Name: opening_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX opening_lod4msrf_fkx ON citydb.opening USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4721 (class 1259 OID 419721)
-- Name: opening_lod4refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX opening_lod4refpt_spx ON citydb.opening USING gist (lod4_implicit_ref_point);


--
-- TOC entry 4722 (class 1259 OID 416814)
-- Name: opening_objectclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX opening_objectclass_fkx ON citydb.opening USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4802 (class 1259 OID 416869)
-- Name: plant_cover_lod1msolid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX plant_cover_lod1msolid_fkx ON citydb.plant_cover USING btree (lod1_multi_solid_id) WITH (fillfactor='90');


--
-- TOC entry 4803 (class 1259 OID 416865)
-- Name: plant_cover_lod1msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX plant_cover_lod1msrf_fkx ON citydb.plant_cover USING btree (lod1_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4804 (class 1259 OID 416870)
-- Name: plant_cover_lod2msolid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX plant_cover_lod2msolid_fkx ON citydb.plant_cover USING btree (lod2_multi_solid_id) WITH (fillfactor='90');


--
-- TOC entry 4805 (class 1259 OID 416866)
-- Name: plant_cover_lod2msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX plant_cover_lod2msrf_fkx ON citydb.plant_cover USING btree (lod2_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4806 (class 1259 OID 416871)
-- Name: plant_cover_lod3msolid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX plant_cover_lod3msolid_fkx ON citydb.plant_cover USING btree (lod3_multi_solid_id) WITH (fillfactor='90');


--
-- TOC entry 4807 (class 1259 OID 416867)
-- Name: plant_cover_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX plant_cover_lod3msrf_fkx ON citydb.plant_cover USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4808 (class 1259 OID 416872)
-- Name: plant_cover_lod4msolid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX plant_cover_lod4msolid_fkx ON citydb.plant_cover USING btree (lod4_multi_solid_id) WITH (fillfactor='90');


--
-- TOC entry 4809 (class 1259 OID 416868)
-- Name: plant_cover_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX plant_cover_lod4msrf_fkx ON citydb.plant_cover USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4810 (class 1259 OID 417106)
-- Name: plant_cover_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX plant_cover_objclass_fkx ON citydb.plant_cover USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4853 (class 1259 OID 416903)
-- Name: raster_relief_coverage_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX raster_relief_coverage_fkx ON citydb.raster_relief USING btree (coverage_id) WITH (fillfactor='90');


--
-- TOC entry 4854 (class 1259 OID 417107)
-- Name: raster_relief_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX raster_relief_objclass_fkx ON citydb.raster_relief USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4765 (class 1259 OID 416843)
-- Name: rel_feat_to_rel_comp_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX rel_feat_to_rel_comp_fkx ON citydb.relief_feat_to_rel_comp USING btree (relief_component_id) WITH (fillfactor='90');


--
-- TOC entry 4766 (class 1259 OID 416844)
-- Name: rel_feat_to_rel_comp_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX rel_feat_to_rel_comp_fkx1 ON citydb.relief_feat_to_rel_comp USING btree (relief_feature_id) WITH (fillfactor='90');


--
-- TOC entry 4761 (class 1259 OID 421197)
-- Name: relief_comp_extent_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX relief_comp_extent_spx ON citydb.relief_component USING gist (extent);


--
-- TOC entry 4762 (class 1259 OID 416841)
-- Name: relief_comp_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX relief_comp_objclass_fkx ON citydb.relief_component USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4769 (class 1259 OID 417108)
-- Name: relief_feat_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX relief_feat_objclass_fkx ON citydb.relief_feature USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4729 (class 1259 OID 416824)
-- Name: room_building_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX room_building_fkx ON citydb.room USING btree (building_id) WITH (fillfactor='90');


--
-- TOC entry 4730 (class 1259 OID 416825)
-- Name: room_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX room_lod4msrf_fkx ON citydb.room USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4731 (class 1259 OID 416826)
-- Name: room_lod4solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX room_lod4solid_fkx ON citydb.room USING btree (lod4_solid_id) WITH (fillfactor='90');


--
-- TOC entry 4732 (class 1259 OID 417109)
-- Name: room_objectclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX room_objectclass_fkx ON citydb.room USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5094 (class 1259 OID 417092)
-- Name: schema_referencing_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX schema_referencing_fkx1 ON citydb.schema_referencing USING btree (referenced_id) WITH (fillfactor='90');


--
-- TOC entry 5095 (class 1259 OID 417093)
-- Name: schema_referencing_fkx2; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX schema_referencing_fkx2 ON citydb.schema_referencing USING btree (referencing_id) WITH (fillfactor='90');


--
-- TOC entry 5090 (class 1259 OID 417084)
-- Name: schema_to_objectclass_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX schema_to_objectclass_fkx1 ON citydb.schema_to_objectclass USING btree (schema_id) WITH (fillfactor='90');


--
-- TOC entry 5091 (class 1259 OID 417085)
-- Name: schema_to_objectclass_fkx2; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX schema_to_objectclass_fkx2 ON citydb.schema_to_objectclass USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4813 (class 1259 OID 416873)
-- Name: sol_veg_obj_lod1brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod1brep_fkx ON citydb.solitary_vegetat_object USING btree (lod1_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4814 (class 1259 OID 416881)
-- Name: sol_veg_obj_lod1impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod1impl_fkx ON citydb.solitary_vegetat_object USING btree (lod1_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4815 (class 1259 OID 419841)
-- Name: sol_veg_obj_lod1refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod1refpt_spx ON citydb.solitary_vegetat_object USING gist (lod1_implicit_ref_point);


--
-- TOC entry 4816 (class 1259 OID 419745)
-- Name: sol_veg_obj_lod1xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod1xgeom_spx ON citydb.solitary_vegetat_object USING gist (lod1_other_geom);


--
-- TOC entry 4817 (class 1259 OID 416874)
-- Name: sol_veg_obj_lod2brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod2brep_fkx ON citydb.solitary_vegetat_object USING btree (lod2_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4818 (class 1259 OID 416882)
-- Name: sol_veg_obj_lod2impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod2impl_fkx ON citydb.solitary_vegetat_object USING btree (lod2_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4819 (class 1259 OID 419865)
-- Name: sol_veg_obj_lod2refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod2refpt_spx ON citydb.solitary_vegetat_object USING gist (lod2_implicit_ref_point);


--
-- TOC entry 4820 (class 1259 OID 419769)
-- Name: sol_veg_obj_lod2xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod2xgeom_spx ON citydb.solitary_vegetat_object USING gist (lod2_other_geom);


--
-- TOC entry 4821 (class 1259 OID 416875)
-- Name: sol_veg_obj_lod3brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod3brep_fkx ON citydb.solitary_vegetat_object USING btree (lod3_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4822 (class 1259 OID 416883)
-- Name: sol_veg_obj_lod3impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod3impl_fkx ON citydb.solitary_vegetat_object USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4823 (class 1259 OID 419889)
-- Name: sol_veg_obj_lod3refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod3refpt_spx ON citydb.solitary_vegetat_object USING gist (lod3_implicit_ref_point);


--
-- TOC entry 4824 (class 1259 OID 419793)
-- Name: sol_veg_obj_lod3xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod3xgeom_spx ON citydb.solitary_vegetat_object USING gist (lod3_other_geom);


--
-- TOC entry 4825 (class 1259 OID 416876)
-- Name: sol_veg_obj_lod4brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod4brep_fkx ON citydb.solitary_vegetat_object USING btree (lod4_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4826 (class 1259 OID 416884)
-- Name: sol_veg_obj_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod4impl_fkx ON citydb.solitary_vegetat_object USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4827 (class 1259 OID 419913)
-- Name: sol_veg_obj_lod4refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod4refpt_spx ON citydb.solitary_vegetat_object USING gist (lod4_implicit_ref_point);


--
-- TOC entry 4828 (class 1259 OID 419817)
-- Name: sol_veg_obj_lod4xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod4xgeom_spx ON citydb.solitary_vegetat_object USING gist (lod4_other_geom);


--
-- TOC entry 4829 (class 1259 OID 417110)
-- Name: sol_veg_obj_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_objclass_fkx ON citydb.solitary_vegetat_object USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5064 (class 1259 OID 417056)
-- Name: surface_data_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX surface_data_inx ON citydb.surface_data USING btree (gmlid, gmlid_codespace) WITH (fillfactor='90');


--
-- TOC entry 5065 (class 1259 OID 417125)
-- Name: surface_data_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX surface_data_objclass_fkx ON citydb.surface_data USING btree (objectclass_id);


--
-- TOC entry 5068 (class 1259 OID 420642)
-- Name: surface_data_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX surface_data_spx ON citydb.surface_data USING gist (gt_reference_point);


--
-- TOC entry 5069 (class 1259 OID 417058)
-- Name: surface_data_tex_image_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX surface_data_tex_image_fkx ON citydb.surface_data USING btree (tex_image_id);


--
-- TOC entry 5052 (class 1259 OID 417055)
-- Name: surface_geom_cityobj_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX surface_geom_cityobj_fkx ON citydb.surface_geometry USING btree (cityobject_id) WITH (fillfactor='90');


--
-- TOC entry 5053 (class 1259 OID 417050)
-- Name: surface_geom_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX surface_geom_inx ON citydb.surface_geometry USING btree (gmlid, gmlid_codespace) WITH (fillfactor='90');


--
-- TOC entry 5054 (class 1259 OID 417051)
-- Name: surface_geom_parent_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX surface_geom_parent_fkx ON citydb.surface_geometry USING btree (parent_id) WITH (fillfactor='90');


--
-- TOC entry 5055 (class 1259 OID 417052)
-- Name: surface_geom_root_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX surface_geom_root_fkx ON citydb.surface_geometry USING btree (root_id) WITH (fillfactor='90');


--
-- TOC entry 5056 (class 1259 OID 421256)
-- Name: surface_geom_solid_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX surface_geom_solid_spx ON citydb.surface_geometry USING gist (solid_geometry);


--
-- TOC entry 5057 (class 1259 OID 421269)
-- Name: surface_geom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX surface_geom_spx ON citydb.surface_geometry USING gist (geometry);


--
-- TOC entry 4744 (class 1259 OID 416834)
-- Name: texparam_geom_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX texparam_geom_fkx ON citydb.textureparam USING btree (surface_geometry_id) WITH (fillfactor='90');


--
-- TOC entry 4745 (class 1259 OID 416835)
-- Name: texparam_surface_data_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX texparam_surface_data_fkx ON citydb.textureparam USING btree (surface_data_id) WITH (fillfactor='90');


--
-- TOC entry 4735 (class 1259 OID 416830)
-- Name: them_surface_bldg_inst_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX them_surface_bldg_inst_fkx ON citydb.thematic_surface USING btree (building_installation_id) WITH (fillfactor='90');


--
-- TOC entry 4736 (class 1259 OID 416828)
-- Name: them_surface_building_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX them_surface_building_fkx ON citydb.thematic_surface USING btree (building_id) WITH (fillfactor='90');


--
-- TOC entry 4737 (class 1259 OID 416831)
-- Name: them_surface_lod2msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX them_surface_lod2msrf_fkx ON citydb.thematic_surface USING btree (lod2_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4738 (class 1259 OID 416832)
-- Name: them_surface_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX them_surface_lod3msrf_fkx ON citydb.thematic_surface USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4739 (class 1259 OID 416833)
-- Name: them_surface_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX them_surface_lod4msrf_fkx ON citydb.thematic_surface USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4740 (class 1259 OID 416827)
-- Name: them_surface_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX them_surface_objclass_fkx ON citydb.thematic_surface USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4741 (class 1259 OID 416829)
-- Name: them_surface_room_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX them_surface_room_fkx ON citydb.thematic_surface USING btree (room_id) WITH (fillfactor='90');


--
-- TOC entry 4772 (class 1259 OID 418837)
-- Name: tin_relief_break_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tin_relief_break_spx ON citydb.tin_relief USING gist (break_lines);


--
-- TOC entry 4773 (class 1259 OID 418849)
-- Name: tin_relief_crtlpts_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tin_relief_crtlpts_spx ON citydb.tin_relief USING gist (control_points);


--
-- TOC entry 4774 (class 1259 OID 416845)
-- Name: tin_relief_geom_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tin_relief_geom_fkx ON citydb.tin_relief USING btree (surface_geometry_id) WITH (fillfactor='90');


--
-- TOC entry 4775 (class 1259 OID 417111)
-- Name: tin_relief_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tin_relief_objclass_fkx ON citydb.tin_relief USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4778 (class 1259 OID 418825)
-- Name: tin_relief_stop_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tin_relief_stop_spx ON citydb.tin_relief USING gist (stop_lines);


--
-- TOC entry 4787 (class 1259 OID 416856)
-- Name: traffic_area_lod2msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX traffic_area_lod2msrf_fkx ON citydb.traffic_area USING btree (lod2_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4788 (class 1259 OID 416857)
-- Name: traffic_area_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX traffic_area_lod3msrf_fkx ON citydb.traffic_area USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4789 (class 1259 OID 416858)
-- Name: traffic_area_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX traffic_area_lod4msrf_fkx ON citydb.traffic_area USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4790 (class 1259 OID 416855)
-- Name: traffic_area_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX traffic_area_objclass_fkx ON citydb.traffic_area USING btree (objectclass_id);


--
-- TOC entry 4793 (class 1259 OID 416859)
-- Name: traffic_area_trancmplx_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX traffic_area_trancmplx_fkx ON citydb.traffic_area USING btree (transportation_complex_id) WITH (fillfactor='90');


--
-- TOC entry 4779 (class 1259 OID 420841)
-- Name: tran_complex_lod0net_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tran_complex_lod0net_spx ON citydb.transportation_complex USING gist (lod0_network);


--
-- TOC entry 4780 (class 1259 OID 416851)
-- Name: tran_complex_lod1msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tran_complex_lod1msrf_fkx ON citydb.transportation_complex USING btree (lod1_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4781 (class 1259 OID 416852)
-- Name: tran_complex_lod2msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tran_complex_lod2msrf_fkx ON citydb.transportation_complex USING btree (lod2_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4782 (class 1259 OID 416853)
-- Name: tran_complex_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tran_complex_lod3msrf_fkx ON citydb.transportation_complex USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4783 (class 1259 OID 416854)
-- Name: tran_complex_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tran_complex_lod4msrf_fkx ON citydb.transportation_complex USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4784 (class 1259 OID 416849)
-- Name: tran_complex_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tran_complex_objclass_fkx ON citydb.transportation_complex USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4881 (class 1259 OID 416924)
-- Name: tun_hspace_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_hspace_lod4msrf_fkx ON citydb.tunnel_hollow_space USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4882 (class 1259 OID 416925)
-- Name: tun_hspace_lod4solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_hspace_lod4solid_fkx ON citydb.tunnel_hollow_space USING btree (lod4_solid_id) WITH (fillfactor='90');


--
-- TOC entry 4883 (class 1259 OID 417114)
-- Name: tun_hspace_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_hspace_objclass_fkx ON citydb.tunnel_hollow_space USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4884 (class 1259 OID 416923)
-- Name: tun_hspace_tunnel_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_hspace_tunnel_fkx ON citydb.tunnel_hollow_space USING btree (tunnel_id) WITH (fillfactor='90');


--
-- TOC entry 4877 (class 1259 OID 416921)
-- Name: tun_open_to_them_srf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_open_to_them_srf_fkx ON citydb.tunnel_open_to_them_srf USING btree (tunnel_opening_id) WITH (fillfactor='90');


--
-- TOC entry 4878 (class 1259 OID 416922)
-- Name: tun_open_to_them_srf_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_open_to_them_srf_fkx1 ON citydb.tunnel_open_to_them_srf USING btree (tunnel_thematic_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4887 (class 1259 OID 416928)
-- Name: tun_them_srf_hspace_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_them_srf_hspace_fkx ON citydb.tunnel_thematic_surface USING btree (tunnel_hollow_space_id) WITH (fillfactor='90');


--
-- TOC entry 4888 (class 1259 OID 416930)
-- Name: tun_them_srf_lod2msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_them_srf_lod2msrf_fkx ON citydb.tunnel_thematic_surface USING btree (lod2_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4889 (class 1259 OID 416931)
-- Name: tun_them_srf_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_them_srf_lod3msrf_fkx ON citydb.tunnel_thematic_surface USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4890 (class 1259 OID 416932)
-- Name: tun_them_srf_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_them_srf_lod4msrf_fkx ON citydb.tunnel_thematic_surface USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4891 (class 1259 OID 416926)
-- Name: tun_them_srf_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_them_srf_objclass_fkx ON citydb.tunnel_thematic_surface USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4892 (class 1259 OID 416929)
-- Name: tun_them_srf_tun_inst_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_them_srf_tun_inst_fkx ON citydb.tunnel_thematic_surface USING btree (tunnel_installation_id) WITH (fillfactor='90');


--
-- TOC entry 4893 (class 1259 OID 416927)
-- Name: tun_them_srf_tunnel_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_them_srf_tunnel_fkx ON citydb.tunnel_thematic_surface USING btree (tunnel_id) WITH (fillfactor='90');


--
-- TOC entry 4922 (class 1259 OID 416955)
-- Name: tunnel_furn_hspace_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_furn_hspace_fkx ON citydb.tunnel_furniture USING btree (tunnel_hollow_space_id) WITH (fillfactor='90');


--
-- TOC entry 4923 (class 1259 OID 416956)
-- Name: tunnel_furn_lod4brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_furn_lod4brep_fkx ON citydb.tunnel_furniture USING btree (lod4_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4924 (class 1259 OID 416958)
-- Name: tunnel_furn_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_furn_lod4impl_fkx ON citydb.tunnel_furniture USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4925 (class 1259 OID 419971)
-- Name: tunnel_furn_lod4refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_furn_lod4refpt_spx ON citydb.tunnel_furniture USING gist (lod4_implicit_ref_point);


--
-- TOC entry 4926 (class 1259 OID 419958)
-- Name: tunnel_furn_lod4xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_furn_lod4xgeom_spx ON citydb.tunnel_furniture USING gist (lod4_other_geom);


--
-- TOC entry 4927 (class 1259 OID 417113)
-- Name: tunnel_furn_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_furn_objclass_fkx ON citydb.tunnel_furniture USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4905 (class 1259 OID 416942)
-- Name: tunnel_inst_hspace_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_hspace_fkx ON citydb.tunnel_installation USING btree (tunnel_hollow_space_id) WITH (fillfactor='90');


--
-- TOC entry 4906 (class 1259 OID 416943)
-- Name: tunnel_inst_lod2brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod2brep_fkx ON citydb.tunnel_installation USING btree (lod2_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4907 (class 1259 OID 416949)
-- Name: tunnel_inst_lod2impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod2impl_fkx ON citydb.tunnel_installation USING btree (lod2_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4908 (class 1259 OID 420569)
-- Name: tunnel_inst_lod2refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod2refpt_spx ON citydb.tunnel_installation USING gist (lod2_implicit_ref_point);


--
-- TOC entry 4909 (class 1259 OID 420503)
-- Name: tunnel_inst_lod2xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod2xgeom_spx ON citydb.tunnel_installation USING gist (lod2_other_geom);


--
-- TOC entry 4910 (class 1259 OID 416944)
-- Name: tunnel_inst_lod3brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod3brep_fkx ON citydb.tunnel_installation USING btree (lod3_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4911 (class 1259 OID 416950)
-- Name: tunnel_inst_lod3impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod3impl_fkx ON citydb.tunnel_installation USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4912 (class 1259 OID 420591)
-- Name: tunnel_inst_lod3refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod3refpt_spx ON citydb.tunnel_installation USING gist (lod3_implicit_ref_point);


--
-- TOC entry 4913 (class 1259 OID 420525)
-- Name: tunnel_inst_lod3xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod3xgeom_spx ON citydb.tunnel_installation USING gist (lod3_other_geom);


--
-- TOC entry 4914 (class 1259 OID 416945)
-- Name: tunnel_inst_lod4brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod4brep_fkx ON citydb.tunnel_installation USING btree (lod4_brep_id) WITH (fillfactor='90');


--
-- TOC entry 4915 (class 1259 OID 416951)
-- Name: tunnel_inst_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod4impl_fkx ON citydb.tunnel_installation USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4916 (class 1259 OID 420613)
-- Name: tunnel_inst_lod4refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod4refpt_spx ON citydb.tunnel_installation USING gist (lod4_implicit_ref_point);


--
-- TOC entry 4917 (class 1259 OID 420547)
-- Name: tunnel_inst_lod4xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod4xgeom_spx ON citydb.tunnel_installation USING gist (lod4_other_geom);


--
-- TOC entry 4918 (class 1259 OID 416940)
-- Name: tunnel_inst_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_objclass_fkx ON citydb.tunnel_installation USING btree (objectclass_id);


--
-- TOC entry 4919 (class 1259 OID 416941)
-- Name: tunnel_inst_tunnel_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_tunnel_fkx ON citydb.tunnel_installation USING btree (tunnel_id) WITH (fillfactor='90');


--
-- TOC entry 4857 (class 1259 OID 416913)
-- Name: tunnel_lod1msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod1msrf_fkx ON citydb.tunnel USING btree (lod1_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4858 (class 1259 OID 416917)
-- Name: tunnel_lod1solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod1solid_fkx ON citydb.tunnel USING btree (lod1_solid_id) WITH (fillfactor='90');


--
-- TOC entry 4859 (class 1259 OID 420678)
-- Name: tunnel_lod1terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod1terr_spx ON citydb.tunnel USING gist (lod1_terrain_intersection);


--
-- TOC entry 4860 (class 1259 OID 420778)
-- Name: tunnel_lod2curve_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod2curve_spx ON citydb.tunnel USING gist (lod2_multi_curve);


--
-- TOC entry 4861 (class 1259 OID 416914)
-- Name: tunnel_lod2msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod2msrf_fkx ON citydb.tunnel USING btree (lod2_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4862 (class 1259 OID 416918)
-- Name: tunnel_lod2solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod2solid_fkx ON citydb.tunnel USING btree (lod2_solid_id) WITH (fillfactor='90');


--
-- TOC entry 4863 (class 1259 OID 420703)
-- Name: tunnel_lod2terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod2terr_spx ON citydb.tunnel USING gist (lod2_terrain_intersection);


--
-- TOC entry 4864 (class 1259 OID 420803)
-- Name: tunnel_lod3curve_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod3curve_spx ON citydb.tunnel USING gist (lod3_multi_curve);


--
-- TOC entry 4865 (class 1259 OID 416915)
-- Name: tunnel_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod3msrf_fkx ON citydb.tunnel USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4866 (class 1259 OID 416919)
-- Name: tunnel_lod3solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod3solid_fkx ON citydb.tunnel USING btree (lod3_solid_id) WITH (fillfactor='90');


--
-- TOC entry 4867 (class 1259 OID 420728)
-- Name: tunnel_lod3terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod3terr_spx ON citydb.tunnel USING gist (lod3_terrain_intersection);


--
-- TOC entry 4868 (class 1259 OID 420828)
-- Name: tunnel_lod4curve_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod4curve_spx ON citydb.tunnel USING gist (lod4_multi_curve);


--
-- TOC entry 4869 (class 1259 OID 416916)
-- Name: tunnel_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod4msrf_fkx ON citydb.tunnel USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4870 (class 1259 OID 416920)
-- Name: tunnel_lod4solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod4solid_fkx ON citydb.tunnel USING btree (lod4_solid_id) WITH (fillfactor='90');


--
-- TOC entry 4871 (class 1259 OID 420753)
-- Name: tunnel_lod4terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod4terr_spx ON citydb.tunnel USING gist (lod4_terrain_intersection);


--
-- TOC entry 4872 (class 1259 OID 417112)
-- Name: tunnel_objectclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_objectclass_fkx ON citydb.tunnel USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4896 (class 1259 OID 416936)
-- Name: tunnel_open_lod3impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_open_lod3impl_fkx ON citydb.tunnel_opening USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4897 (class 1259 OID 416934)
-- Name: tunnel_open_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_open_lod3msrf_fkx ON citydb.tunnel_opening USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4898 (class 1259 OID 421283)
-- Name: tunnel_open_lod3refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_open_lod3refpt_spx ON citydb.tunnel_opening USING gist (lod3_implicit_ref_point);


--
-- TOC entry 4899 (class 1259 OID 416937)
-- Name: tunnel_open_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_open_lod4impl_fkx ON citydb.tunnel_opening USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 4900 (class 1259 OID 416935)
-- Name: tunnel_open_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_open_lod4msrf_fkx ON citydb.tunnel_opening USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4901 (class 1259 OID 421297)
-- Name: tunnel_open_lod4refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_open_lod4refpt_spx ON citydb.tunnel_opening USING gist (lod4_implicit_ref_point);


--
-- TOC entry 4902 (class 1259 OID 416933)
-- Name: tunnel_open_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_open_objclass_fkx ON citydb.tunnel_opening USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4873 (class 1259 OID 416904)
-- Name: tunnel_parent_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_parent_fkx ON citydb.tunnel USING btree (tunnel_parent_id) WITH (fillfactor='90');


--
-- TOC entry 4876 (class 1259 OID 416905)
-- Name: tunnel_root_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_root_fkx ON citydb.tunnel USING btree (tunnel_root_id) WITH (fillfactor='90');


--
-- TOC entry 4847 (class 1259 OID 416900)
-- Name: waterbnd_srf_lod2srf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbnd_srf_lod2srf_fkx ON citydb.waterboundary_surface USING btree (lod2_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4848 (class 1259 OID 416901)
-- Name: waterbnd_srf_lod3srf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbnd_srf_lod3srf_fkx ON citydb.waterboundary_surface USING btree (lod3_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4849 (class 1259 OID 416902)
-- Name: waterbnd_srf_lod4srf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbnd_srf_lod4srf_fkx ON citydb.waterboundary_surface USING btree (lod4_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4850 (class 1259 OID 416899)
-- Name: waterbnd_srf_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbnd_srf_objclass_fkx ON citydb.waterboundary_surface USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 4843 (class 1259 OID 416897)
-- Name: waterbod_to_waterbnd_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbod_to_waterbnd_fkx ON citydb.waterbod_to_waterbnd_srf USING btree (waterboundary_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4844 (class 1259 OID 416898)
-- Name: waterbod_to_waterbnd_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbod_to_waterbnd_fkx1 ON citydb.waterbod_to_waterbnd_srf USING btree (waterbody_id) WITH (fillfactor='90');


--
-- TOC entry 4832 (class 1259 OID 419929)
-- Name: waterbody_lod0curve_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbody_lod0curve_spx ON citydb.waterbody USING gist (lod0_multi_curve);


--
-- TOC entry 4833 (class 1259 OID 416891)
-- Name: waterbody_lod0msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbody_lod0msrf_fkx ON citydb.waterbody USING btree (lod0_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4834 (class 1259 OID 419945)
-- Name: waterbody_lod1curve_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbody_lod1curve_spx ON citydb.waterbody USING gist (lod1_multi_curve);


--
-- TOC entry 4835 (class 1259 OID 416892)
-- Name: waterbody_lod1msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbody_lod1msrf_fkx ON citydb.waterbody USING btree (lod1_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 4836 (class 1259 OID 416893)
-- Name: waterbody_lod1solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbody_lod1solid_fkx ON citydb.waterbody USING btree (lod1_solid_id) WITH (fillfactor='90');


--
-- TOC entry 4837 (class 1259 OID 416894)
-- Name: waterbody_lod2solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbody_lod2solid_fkx ON citydb.waterbody USING btree (lod2_solid_id) WITH (fillfactor='90');


--
-- TOC entry 4838 (class 1259 OID 416895)
-- Name: waterbody_lod3solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbody_lod3solid_fkx ON citydb.waterbody USING btree (lod3_solid_id) WITH (fillfactor='90');


--
-- TOC entry 4839 (class 1259 OID 416896)
-- Name: waterbody_lod4solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbody_lod4solid_fkx ON citydb.waterbody USING btree (lod4_solid_id) WITH (fillfactor='90');


--
-- TOC entry 4840 (class 1259 OID 417115)
-- Name: waterbody_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbody_objclass_fkx ON citydb.waterbody USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5375 (class 2606 OID 418492)
-- Name: address_to_bridge address_to_bridge_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.address_to_bridge
    ADD CONSTRAINT address_to_bridge_fk FOREIGN KEY (address_id) REFERENCES citydb.address(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5376 (class 2606 OID 418497)
-- Name: address_to_bridge address_to_bridge_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.address_to_bridge
    ADD CONSTRAINT address_to_bridge_fk1 FOREIGN KEY (bridge_id) REFERENCES citydb.bridge(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5139 (class 2606 OID 417312)
-- Name: address_to_building address_to_building_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.address_to_building
    ADD CONSTRAINT address_to_building_fk FOREIGN KEY (address_id) REFERENCES citydb.address(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5140 (class 2606 OID 417317)
-- Name: address_to_building address_to_building_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.address_to_building
    ADD CONSTRAINT address_to_building_fk1 FOREIGN KEY (building_id) REFERENCES citydb.building(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5396 (class 2606 OID 418597)
-- Name: aggregation_info aggregation_info_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.aggregation_info
    ADD CONSTRAINT aggregation_info_fk1 FOREIGN KEY (child_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5397 (class 2606 OID 418602)
-- Name: aggregation_info aggregation_info_fk2; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.aggregation_info
    ADD CONSTRAINT aggregation_info_fk2 FOREIGN KEY (parent_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5194 (class 2606 OID 417587)
-- Name: appear_to_surface_data app_to_surf_data_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.appear_to_surface_data
    ADD CONSTRAINT app_to_surf_data_fk FOREIGN KEY (surface_data_id) REFERENCES citydb.surface_data(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5195 (class 2606 OID 417592)
-- Name: appear_to_surface_data app_to_surf_data_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.appear_to_surface_data
    ADD CONSTRAINT app_to_surf_data_fk1 FOREIGN KEY (appearance_id) REFERENCES citydb.appearance(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5379 (class 2606 OID 418512)
-- Name: appearance appearance_citymodel_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.appearance
    ADD CONSTRAINT appearance_citymodel_fk FOREIGN KEY (citymodel_id) REFERENCES citydb.citymodel(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5378 (class 2606 OID 418507)
-- Name: appearance appearance_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.appearance
    ADD CONSTRAINT appearance_cityobject_fk FOREIGN KEY (cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5155 (class 2606 OID 417392)
-- Name: building_furniture bldg_furn_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_furniture
    ADD CONSTRAINT bldg_furn_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5157 (class 2606 OID 417402)
-- Name: building_furniture bldg_furn_lod4brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_furniture
    ADD CONSTRAINT bldg_furn_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5158 (class 2606 OID 417407)
-- Name: building_furniture bldg_furn_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_furniture
    ADD CONSTRAINT bldg_furn_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5159 (class 2606 OID 417412)
-- Name: building_furniture bldg_furn_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_furniture
    ADD CONSTRAINT bldg_furn_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5156 (class 2606 OID 417397)
-- Name: building_furniture bldg_furn_room_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_furniture
    ADD CONSTRAINT bldg_furn_room_fk FOREIGN KEY (room_id) REFERENCES citydb.room(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5162 (class 2606 OID 417427)
-- Name: building_installation bldg_inst_building_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_building_fk FOREIGN KEY (building_id) REFERENCES citydb.building(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5160 (class 2606 OID 417417)
-- Name: building_installation bldg_inst_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5164 (class 2606 OID 417437)
-- Name: building_installation bldg_inst_lod2brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_lod2brep_fk FOREIGN KEY (lod2_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5167 (class 2606 OID 417452)
-- Name: building_installation bldg_inst_lod2impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_lod2impl_fk FOREIGN KEY (lod2_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5165 (class 2606 OID 417442)
-- Name: building_installation bldg_inst_lod3brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_lod3brep_fk FOREIGN KEY (lod3_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5168 (class 2606 OID 417457)
-- Name: building_installation bldg_inst_lod3impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5166 (class 2606 OID 417447)
-- Name: building_installation bldg_inst_lod4brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5169 (class 2606 OID 417462)
-- Name: building_installation bldg_inst_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5161 (class 2606 OID 417422)
-- Name: building_installation bldg_inst_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5163 (class 2606 OID 417432)
-- Name: building_installation bldg_inst_room_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_room_fk FOREIGN KEY (room_id) REFERENCES citydb.room(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5348 (class 2606 OID 418357)
-- Name: bridge_open_to_them_srf brd_open_to_them_srf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_open_to_them_srf
    ADD CONSTRAINT brd_open_to_them_srf_fk FOREIGN KEY (bridge_opening_id) REFERENCES citydb.bridge_opening(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5349 (class 2606 OID 418362)
-- Name: bridge_open_to_them_srf brd_open_to_them_srf_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_open_to_them_srf
    ADD CONSTRAINT brd_open_to_them_srf_fk1 FOREIGN KEY (bridge_thematic_surface_id) REFERENCES citydb.bridge_thematic_surface(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5360 (class 2606 OID 418417)
-- Name: bridge_thematic_surface brd_them_srf_brd_const_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_brd_const_fk FOREIGN KEY (bridge_constr_element_id) REFERENCES citydb.bridge_constr_element(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5359 (class 2606 OID 418412)
-- Name: bridge_thematic_surface brd_them_srf_brd_inst_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_brd_inst_fk FOREIGN KEY (bridge_installation_id) REFERENCES citydb.bridge_installation(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5358 (class 2606 OID 418407)
-- Name: bridge_thematic_surface brd_them_srf_brd_room_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_brd_room_fk FOREIGN KEY (bridge_room_id) REFERENCES citydb.bridge_room(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5357 (class 2606 OID 418402)
-- Name: bridge_thematic_surface brd_them_srf_bridge_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_bridge_fk FOREIGN KEY (bridge_id) REFERENCES citydb.bridge(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5355 (class 2606 OID 418392)
-- Name: bridge_thematic_surface brd_them_srf_cityobj_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_cityobj_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5361 (class 2606 OID 418422)
-- Name: bridge_thematic_surface brd_them_srf_lod2msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5362 (class 2606 OID 418427)
-- Name: bridge_thematic_surface brd_them_srf_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5363 (class 2606 OID 418432)
-- Name: bridge_thematic_surface brd_them_srf_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5356 (class 2606 OID 418397)
-- Name: bridge_thematic_surface brd_them_srf_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5197 (class 2606 OID 417602)
-- Name: breakline_relief breakline_rel_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.breakline_relief
    ADD CONSTRAINT breakline_rel_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5196 (class 2606 OID 417597)
-- Name: breakline_relief breakline_relief_comp_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.breakline_relief
    ADD CONSTRAINT breakline_relief_comp_fk FOREIGN KEY (id) REFERENCES citydb.relief_component(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5314 (class 2606 OID 418187)
-- Name: bridge bridge_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5365 (class 2606 OID 418442)
-- Name: bridge_constr_element bridge_constr_bridge_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_bridge_fk FOREIGN KEY (bridge_id) REFERENCES citydb.bridge(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5364 (class 2606 OID 418437)
-- Name: bridge_constr_element bridge_constr_cityobj_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_cityobj_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5366 (class 2606 OID 418447)
-- Name: bridge_constr_element bridge_constr_lod1brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod1brep_fk FOREIGN KEY (lod1_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5370 (class 2606 OID 418467)
-- Name: bridge_constr_element bridge_constr_lod1impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod1impl_fk FOREIGN KEY (lod1_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5367 (class 2606 OID 418452)
-- Name: bridge_constr_element bridge_constr_lod2brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod2brep_fk FOREIGN KEY (lod2_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5371 (class 2606 OID 418472)
-- Name: bridge_constr_element bridge_constr_lod2impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod2impl_fk FOREIGN KEY (lod2_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5368 (class 2606 OID 418457)
-- Name: bridge_constr_element bridge_constr_lod3brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod3brep_fk FOREIGN KEY (lod3_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5372 (class 2606 OID 418477)
-- Name: bridge_constr_element bridge_constr_lod3impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5369 (class 2606 OID 418462)
-- Name: bridge_constr_element bridge_constr_lod4brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5373 (class 2606 OID 418482)
-- Name: bridge_constr_element bridge_constr_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5374 (class 2606 OID 418487)
-- Name: bridge_constr_element bridge_constr_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5327 (class 2606 OID 418252)
-- Name: bridge_furniture bridge_furn_brd_room_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_furniture
    ADD CONSTRAINT bridge_furn_brd_room_fk FOREIGN KEY (bridge_room_id) REFERENCES citydb.bridge_room(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5326 (class 2606 OID 418247)
-- Name: bridge_furniture bridge_furn_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_furniture
    ADD CONSTRAINT bridge_furn_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5328 (class 2606 OID 418257)
-- Name: bridge_furniture bridge_furn_lod4brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_furniture
    ADD CONSTRAINT bridge_furn_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5329 (class 2606 OID 418262)
-- Name: bridge_furniture bridge_furn_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_furniture
    ADD CONSTRAINT bridge_furn_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5330 (class 2606 OID 418267)
-- Name: bridge_furniture bridge_furn_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_furniture
    ADD CONSTRAINT bridge_furn_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5334 (class 2606 OID 418287)
-- Name: bridge_installation bridge_inst_brd_room_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_brd_room_fk FOREIGN KEY (bridge_room_id) REFERENCES citydb.bridge_room(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5333 (class 2606 OID 418282)
-- Name: bridge_installation bridge_inst_bridge_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_bridge_fk FOREIGN KEY (bridge_id) REFERENCES citydb.bridge(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5331 (class 2606 OID 418272)
-- Name: bridge_installation bridge_inst_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5335 (class 2606 OID 418292)
-- Name: bridge_installation bridge_inst_lod2brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_lod2brep_fk FOREIGN KEY (lod2_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5338 (class 2606 OID 418307)
-- Name: bridge_installation bridge_inst_lod2impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_lod2impl_fk FOREIGN KEY (lod2_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5336 (class 2606 OID 418297)
-- Name: bridge_installation bridge_inst_lod3brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_lod3brep_fk FOREIGN KEY (lod3_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5339 (class 2606 OID 418312)
-- Name: bridge_installation bridge_inst_lod3impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5337 (class 2606 OID 418302)
-- Name: bridge_installation bridge_inst_lod4brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5340 (class 2606 OID 418317)
-- Name: bridge_installation bridge_inst_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5332 (class 2606 OID 418277)
-- Name: bridge_installation bridge_inst_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5317 (class 2606 OID 418202)
-- Name: bridge bridge_lod1msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod1msrf_fk FOREIGN KEY (lod1_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5321 (class 2606 OID 418222)
-- Name: bridge bridge_lod1solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod1solid_fk FOREIGN KEY (lod1_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5318 (class 2606 OID 418207)
-- Name: bridge bridge_lod2msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5322 (class 2606 OID 418227)
-- Name: bridge bridge_lod2solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod2solid_fk FOREIGN KEY (lod2_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5319 (class 2606 OID 418212)
-- Name: bridge bridge_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5323 (class 2606 OID 418232)
-- Name: bridge bridge_lod3solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod3solid_fk FOREIGN KEY (lod3_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5320 (class 2606 OID 418217)
-- Name: bridge bridge_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5324 (class 2606 OID 418237)
-- Name: bridge bridge_lod4solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod4solid_fk FOREIGN KEY (lod4_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5325 (class 2606 OID 418242)
-- Name: bridge bridge_objectclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_objectclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5343 (class 2606 OID 418332)
-- Name: bridge_opening bridge_open_address_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_open_address_fk FOREIGN KEY (address_id) REFERENCES citydb.address(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5341 (class 2606 OID 418322)
-- Name: bridge_opening bridge_open_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_open_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5346 (class 2606 OID 418347)
-- Name: bridge_opening bridge_open_lod3impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_open_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5344 (class 2606 OID 418337)
-- Name: bridge_opening bridge_open_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_open_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5347 (class 2606 OID 418352)
-- Name: bridge_opening bridge_open_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_open_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5345 (class 2606 OID 418342)
-- Name: bridge_opening bridge_open_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_open_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5342 (class 2606 OID 418327)
-- Name: bridge_opening bridge_open_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_open_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5315 (class 2606 OID 418192)
-- Name: bridge bridge_parent_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_parent_fk FOREIGN KEY (bridge_parent_id) REFERENCES citydb.bridge(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5351 (class 2606 OID 418372)
-- Name: bridge_room bridge_room_bridge_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_room
    ADD CONSTRAINT bridge_room_bridge_fk FOREIGN KEY (bridge_id) REFERENCES citydb.bridge(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5350 (class 2606 OID 418367)
-- Name: bridge_room bridge_room_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_room
    ADD CONSTRAINT bridge_room_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5352 (class 2606 OID 418377)
-- Name: bridge_room bridge_room_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_room
    ADD CONSTRAINT bridge_room_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5353 (class 2606 OID 418382)
-- Name: bridge_room bridge_room_lod4solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_room
    ADD CONSTRAINT bridge_room_lod4solid_fk FOREIGN KEY (lod4_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5354 (class 2606 OID 418387)
-- Name: bridge_room bridge_room_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_room
    ADD CONSTRAINT bridge_room_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5316 (class 2606 OID 418197)
-- Name: bridge bridge_root_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_root_fk FOREIGN KEY (bridge_root_id) REFERENCES citydb.bridge(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5141 (class 2606 OID 417322)
-- Name: building building_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5144 (class 2606 OID 417337)
-- Name: building building_lod0footprint_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod0footprint_fk FOREIGN KEY (lod0_footprint_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5145 (class 2606 OID 417342)
-- Name: building building_lod0roofprint_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod0roofprint_fk FOREIGN KEY (lod0_roofprint_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5146 (class 2606 OID 417347)
-- Name: building building_lod1msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod1msrf_fk FOREIGN KEY (lod1_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5150 (class 2606 OID 417367)
-- Name: building building_lod1solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod1solid_fk FOREIGN KEY (lod1_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5147 (class 2606 OID 417352)
-- Name: building building_lod2msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5151 (class 2606 OID 417372)
-- Name: building building_lod2solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod2solid_fk FOREIGN KEY (lod2_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5148 (class 2606 OID 417357)
-- Name: building building_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5152 (class 2606 OID 417377)
-- Name: building building_lod3solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod3solid_fk FOREIGN KEY (lod3_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5149 (class 2606 OID 417362)
-- Name: building building_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5153 (class 2606 OID 417382)
-- Name: building building_lod4solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod4solid_fk FOREIGN KEY (lod4_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5154 (class 2606 OID 417387)
-- Name: building building_objectclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_objectclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5142 (class 2606 OID 417327)
-- Name: building building_parent_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_parent_fk FOREIGN KEY (building_parent_id) REFERENCES citydb.building(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5143 (class 2606 OID 417332)
-- Name: building building_root_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_root_fk FOREIGN KEY (building_root_id) REFERENCES citydb.building(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5117 (class 2606 OID 417202)
-- Name: city_furniture city_furn_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5118 (class 2606 OID 417207)
-- Name: city_furniture city_furn_lod1brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod1brep_fk FOREIGN KEY (lod1_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5122 (class 2606 OID 417227)
-- Name: city_furniture city_furn_lod1impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod1impl_fk FOREIGN KEY (lod1_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5119 (class 2606 OID 417212)
-- Name: city_furniture city_furn_lod2brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod2brep_fk FOREIGN KEY (lod2_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5123 (class 2606 OID 417232)
-- Name: city_furniture city_furn_lod2impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod2impl_fk FOREIGN KEY (lod2_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5120 (class 2606 OID 417217)
-- Name: city_furniture city_furn_lod3brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod3brep_fk FOREIGN KEY (lod3_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5124 (class 2606 OID 417237)
-- Name: city_furniture city_furn_lod3impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5121 (class 2606 OID 417222)
-- Name: city_furniture city_furn_lod4brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5125 (class 2606 OID 417242)
-- Name: city_furniture city_furn_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5126 (class 2606 OID 417247)
-- Name: city_furniture city_furn_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5104 (class 2606 OID 417137)
-- Name: cityobject_member cityobject_member_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobject_member
    ADD CONSTRAINT cityobject_member_fk FOREIGN KEY (cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5105 (class 2606 OID 417142)
-- Name: cityobject_member cityobject_member_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobject_member
    ADD CONSTRAINT cityobject_member_fk1 FOREIGN KEY (citymodel_id) REFERENCES citydb.citymodel(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5377 (class 2606 OID 418502)
-- Name: cityobject cityobject_objectclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobject
    ADD CONSTRAINT cityobject_objectclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5390 (class 2606 OID 418567)
-- Name: external_reference ext_ref_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.external_reference
    ADD CONSTRAINT ext_ref_cityobject_fk FOREIGN KEY (cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5127 (class 2606 OID 417252)
-- Name: generic_cityobject gen_object_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5128 (class 2606 OID 417257)
-- Name: generic_cityobject gen_object_lod0brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod0brep_fk FOREIGN KEY (lod0_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5133 (class 2606 OID 417282)
-- Name: generic_cityobject gen_object_lod0impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod0impl_fk FOREIGN KEY (lod0_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5129 (class 2606 OID 417262)
-- Name: generic_cityobject gen_object_lod1brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod1brep_fk FOREIGN KEY (lod1_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5134 (class 2606 OID 417287)
-- Name: generic_cityobject gen_object_lod1impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod1impl_fk FOREIGN KEY (lod1_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5130 (class 2606 OID 417267)
-- Name: generic_cityobject gen_object_lod2brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod2brep_fk FOREIGN KEY (lod2_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5135 (class 2606 OID 417292)
-- Name: generic_cityobject gen_object_lod2impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod2impl_fk FOREIGN KEY (lod2_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5131 (class 2606 OID 417272)
-- Name: generic_cityobject gen_object_lod3brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod3brep_fk FOREIGN KEY (lod3_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5136 (class 2606 OID 417297)
-- Name: generic_cityobject gen_object_lod3impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5132 (class 2606 OID 417277)
-- Name: generic_cityobject gen_object_lod4brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5137 (class 2606 OID 417302)
-- Name: generic_cityobject gen_object_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5138 (class 2606 OID 417307)
-- Name: generic_cityobject gen_object_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5106 (class 2606 OID 417147)
-- Name: generalization general_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generalization
    ADD CONSTRAINT general_cityobject_fk FOREIGN KEY (cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5107 (class 2606 OID 417152)
-- Name: generalization general_generalizes_to_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generalization
    ADD CONSTRAINT general_generalizes_to_fk FOREIGN KEY (generalizes_to_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5389 (class 2606 OID 418562)
-- Name: cityobject_genericattrib genericattrib_cityobj_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobject_genericattrib
    ADD CONSTRAINT genericattrib_cityobj_fk FOREIGN KEY (cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5388 (class 2606 OID 418557)
-- Name: cityobject_genericattrib genericattrib_geom_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobject_genericattrib
    ADD CONSTRAINT genericattrib_geom_fk FOREIGN KEY (surface_geometry_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5386 (class 2606 OID 418547)
-- Name: cityobject_genericattrib genericattrib_parent_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobject_genericattrib
    ADD CONSTRAINT genericattrib_parent_fk FOREIGN KEY (parent_genattrib_id) REFERENCES citydb.cityobject_genericattrib(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5387 (class 2606 OID 418552)
-- Name: cityobject_genericattrib genericattrib_root_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobject_genericattrib
    ADD CONSTRAINT genericattrib_root_fk FOREIGN KEY (root_genattrib_id) REFERENCES citydb.cityobject_genericattrib(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5109 (class 2606 OID 417162)
-- Name: cityobjectgroup group_brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobjectgroup
    ADD CONSTRAINT group_brep_fk FOREIGN KEY (brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5108 (class 2606 OID 417157)
-- Name: cityobjectgroup group_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobjectgroup
    ADD CONSTRAINT group_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5111 (class 2606 OID 417172)
-- Name: cityobjectgroup group_objectclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobjectgroup
    ADD CONSTRAINT group_objectclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5110 (class 2606 OID 417167)
-- Name: cityobjectgroup group_parent_cityobj_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobjectgroup
    ADD CONSTRAINT group_parent_cityobj_fk FOREIGN KEY (parent_cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5112 (class 2606 OID 417177)
-- Name: group_to_cityobject group_to_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.group_to_cityobject
    ADD CONSTRAINT group_to_cityobject_fk FOREIGN KEY (cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5113 (class 2606 OID 417182)
-- Name: group_to_cityobject group_to_cityobject_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.group_to_cityobject
    ADD CONSTRAINT group_to_cityobject_fk1 FOREIGN KEY (cityobjectgroup_id) REFERENCES citydb.cityobjectgroup(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5380 (class 2606 OID 418517)
-- Name: implicit_geometry implicit_geom_brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.implicit_geometry
    ADD CONSTRAINT implicit_geom_brep_fk FOREIGN KEY (relative_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5221 (class 2606 OID 417722)
-- Name: land_use land_use_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5222 (class 2606 OID 417727)
-- Name: land_use land_use_lod0msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_lod0msrf_fk FOREIGN KEY (lod0_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5223 (class 2606 OID 417732)
-- Name: land_use land_use_lod1msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_lod1msrf_fk FOREIGN KEY (lod1_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5224 (class 2606 OID 417737)
-- Name: land_use land_use_lod2msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5225 (class 2606 OID 417742)
-- Name: land_use land_use_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5226 (class 2606 OID 417747)
-- Name: land_use land_use_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5227 (class 2606 OID 417752)
-- Name: land_use land_use_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5199 (class 2606 OID 417612)
-- Name: masspoint_relief masspoint_rel_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.masspoint_relief
    ADD CONSTRAINT masspoint_rel_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5198 (class 2606 OID 417607)
-- Name: masspoint_relief masspoint_relief_comp_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.masspoint_relief
    ADD CONSTRAINT masspoint_relief_comp_fk FOREIGN KEY (id) REFERENCES citydb.relief_component(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5116 (class 2606 OID 417197)
-- Name: objectclass objectclass_ade_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.objectclass
    ADD CONSTRAINT objectclass_ade_fk FOREIGN KEY (ade_id) REFERENCES citydb.ade(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5115 (class 2606 OID 417192)
-- Name: objectclass objectclass_baseclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.objectclass
    ADD CONSTRAINT objectclass_baseclass_fk FOREIGN KEY (baseclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5114 (class 2606 OID 417187)
-- Name: objectclass objectclass_superclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.objectclass
    ADD CONSTRAINT objectclass_superclass_fk FOREIGN KEY (superclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5177 (class 2606 OID 417502)
-- Name: opening_to_them_surface open_to_them_surface_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.opening_to_them_surface
    ADD CONSTRAINT open_to_them_surface_fk FOREIGN KEY (opening_id) REFERENCES citydb.opening(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5178 (class 2606 OID 417507)
-- Name: opening_to_them_surface open_to_them_surface_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.opening_to_them_surface
    ADD CONSTRAINT open_to_them_surface_fk1 FOREIGN KEY (thematic_surface_id) REFERENCES citydb.thematic_surface(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5172 (class 2606 OID 417477)
-- Name: opening opening_address_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_address_fk FOREIGN KEY (address_id) REFERENCES citydb.address(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5170 (class 2606 OID 417467)
-- Name: opening opening_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5175 (class 2606 OID 417492)
-- Name: opening opening_lod3impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5173 (class 2606 OID 417482)
-- Name: opening opening_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5176 (class 2606 OID 417497)
-- Name: opening opening_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5174 (class 2606 OID 417487)
-- Name: opening opening_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5171 (class 2606 OID 417472)
-- Name: opening opening_objectclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_objectclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5228 (class 2606 OID 417757)
-- Name: plant_cover plant_cover_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5233 (class 2606 OID 417782)
-- Name: plant_cover plant_cover_lod1msolid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod1msolid_fk FOREIGN KEY (lod1_multi_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5229 (class 2606 OID 417762)
-- Name: plant_cover plant_cover_lod1msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod1msrf_fk FOREIGN KEY (lod1_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5234 (class 2606 OID 417787)
-- Name: plant_cover plant_cover_lod2msolid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod2msolid_fk FOREIGN KEY (lod2_multi_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5230 (class 2606 OID 417767)
-- Name: plant_cover plant_cover_lod2msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5235 (class 2606 OID 417792)
-- Name: plant_cover plant_cover_lod3msolid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod3msolid_fk FOREIGN KEY (lod3_multi_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5231 (class 2606 OID 417772)
-- Name: plant_cover plant_cover_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5236 (class 2606 OID 417797)
-- Name: plant_cover plant_cover_lod4msolid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod4msolid_fk FOREIGN KEY (lod4_multi_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5232 (class 2606 OID 417777)
-- Name: plant_cover plant_cover_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5237 (class 2606 OID 417802)
-- Name: plant_cover plant_cover_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5263 (class 2606 OID 417932)
-- Name: raster_relief raster_relief_comp_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.raster_relief
    ADD CONSTRAINT raster_relief_comp_fk FOREIGN KEY (id) REFERENCES citydb.relief_component(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5264 (class 2606 OID 417937)
-- Name: raster_relief raster_relief_coverage_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.raster_relief
    ADD CONSTRAINT raster_relief_coverage_fk FOREIGN KEY (coverage_id) REFERENCES citydb.grid_coverage(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5265 (class 2606 OID 417942)
-- Name: raster_relief raster_relief_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.raster_relief
    ADD CONSTRAINT raster_relief_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5202 (class 2606 OID 417627)
-- Name: relief_feat_to_rel_comp rel_feat_to_rel_comp_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.relief_feat_to_rel_comp
    ADD CONSTRAINT rel_feat_to_rel_comp_fk FOREIGN KEY (relief_component_id) REFERENCES citydb.relief_component(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5203 (class 2606 OID 417632)
-- Name: relief_feat_to_rel_comp rel_feat_to_rel_comp_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.relief_feat_to_rel_comp
    ADD CONSTRAINT rel_feat_to_rel_comp_fk1 FOREIGN KEY (relief_feature_id) REFERENCES citydb.relief_feature(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5200 (class 2606 OID 417617)
-- Name: relief_component relief_comp_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.relief_component
    ADD CONSTRAINT relief_comp_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5201 (class 2606 OID 417622)
-- Name: relief_component relief_comp_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.relief_component
    ADD CONSTRAINT relief_comp_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5204 (class 2606 OID 417637)
-- Name: relief_feature relief_feat_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.relief_feature
    ADD CONSTRAINT relief_feat_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5205 (class 2606 OID 417642)
-- Name: relief_feature relief_feat_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.relief_feature
    ADD CONSTRAINT relief_feat_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5180 (class 2606 OID 417517)
-- Name: room room_building_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.room
    ADD CONSTRAINT room_building_fk FOREIGN KEY (building_id) REFERENCES citydb.building(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5179 (class 2606 OID 417512)
-- Name: room room_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.room
    ADD CONSTRAINT room_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5181 (class 2606 OID 417522)
-- Name: room room_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.room
    ADD CONSTRAINT room_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5182 (class 2606 OID 417527)
-- Name: room room_lod4solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.room
    ADD CONSTRAINT room_lod4solid_fk FOREIGN KEY (lod4_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5183 (class 2606 OID 417532)
-- Name: room room_objectclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.room
    ADD CONSTRAINT room_objectclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5391 (class 2606 OID 418572)
-- Name: schema schema_ade_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.schema
    ADD CONSTRAINT schema_ade_fk FOREIGN KEY (ade_id) REFERENCES citydb.ade(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5394 (class 2606 OID 418587)
-- Name: schema_referencing schema_referencing_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.schema_referencing
    ADD CONSTRAINT schema_referencing_fk1 FOREIGN KEY (referencing_id) REFERENCES citydb.schema(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5395 (class 2606 OID 418592)
-- Name: schema_referencing schema_referencing_fk2; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.schema_referencing
    ADD CONSTRAINT schema_referencing_fk2 FOREIGN KEY (referenced_id) REFERENCES citydb.schema(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5392 (class 2606 OID 418577)
-- Name: schema_to_objectclass schema_to_objectclass_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.schema_to_objectclass
    ADD CONSTRAINT schema_to_objectclass_fk1 FOREIGN KEY (schema_id) REFERENCES citydb.schema(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5393 (class 2606 OID 418582)
-- Name: schema_to_objectclass schema_to_objectclass_fk2; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.schema_to_objectclass
    ADD CONSTRAINT schema_to_objectclass_fk2 FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5238 (class 2606 OID 417807)
-- Name: solitary_vegetat_object sol_veg_obj_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5239 (class 2606 OID 417812)
-- Name: solitary_vegetat_object sol_veg_obj_lod1brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod1brep_fk FOREIGN KEY (lod1_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5243 (class 2606 OID 417832)
-- Name: solitary_vegetat_object sol_veg_obj_lod1impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod1impl_fk FOREIGN KEY (lod1_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5240 (class 2606 OID 417817)
-- Name: solitary_vegetat_object sol_veg_obj_lod2brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod2brep_fk FOREIGN KEY (lod2_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5244 (class 2606 OID 417837)
-- Name: solitary_vegetat_object sol_veg_obj_lod2impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod2impl_fk FOREIGN KEY (lod2_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5241 (class 2606 OID 417822)
-- Name: solitary_vegetat_object sol_veg_obj_lod3brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod3brep_fk FOREIGN KEY (lod3_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5245 (class 2606 OID 417842)
-- Name: solitary_vegetat_object sol_veg_obj_lod3impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5242 (class 2606 OID 417827)
-- Name: solitary_vegetat_object sol_veg_obj_lod4brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5246 (class 2606 OID 417847)
-- Name: solitary_vegetat_object sol_veg_obj_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5247 (class 2606 OID 417852)
-- Name: solitary_vegetat_object sol_veg_obj_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5385 (class 2606 OID 418542)
-- Name: surface_data surface_data_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.surface_data
    ADD CONSTRAINT surface_data_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5384 (class 2606 OID 418537)
-- Name: surface_data surface_data_tex_image_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.surface_data
    ADD CONSTRAINT surface_data_tex_image_fk FOREIGN KEY (tex_image_id) REFERENCES citydb.tex_image(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5383 (class 2606 OID 418532)
-- Name: surface_geometry surface_geom_cityobj_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.surface_geometry
    ADD CONSTRAINT surface_geom_cityobj_fk FOREIGN KEY (cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5381 (class 2606 OID 418522)
-- Name: surface_geometry surface_geom_parent_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.surface_geometry
    ADD CONSTRAINT surface_geom_parent_fk FOREIGN KEY (parent_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5382 (class 2606 OID 418527)
-- Name: surface_geometry surface_geom_root_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.surface_geometry
    ADD CONSTRAINT surface_geom_root_fk FOREIGN KEY (root_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5192 (class 2606 OID 417577)
-- Name: textureparam texparam_geom_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.textureparam
    ADD CONSTRAINT texparam_geom_fk FOREIGN KEY (surface_geometry_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5193 (class 2606 OID 417582)
-- Name: textureparam texparam_surface_data_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.textureparam
    ADD CONSTRAINT texparam_surface_data_fk FOREIGN KEY (surface_data_id) REFERENCES citydb.surface_data(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5188 (class 2606 OID 417557)
-- Name: thematic_surface them_surface_bldg_inst_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_bldg_inst_fk FOREIGN KEY (building_installation_id) REFERENCES citydb.building_installation(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5186 (class 2606 OID 417547)
-- Name: thematic_surface them_surface_building_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_building_fk FOREIGN KEY (building_id) REFERENCES citydb.building(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5184 (class 2606 OID 417537)
-- Name: thematic_surface them_surface_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5189 (class 2606 OID 417562)
-- Name: thematic_surface them_surface_lod2msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5190 (class 2606 OID 417567)
-- Name: thematic_surface them_surface_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5191 (class 2606 OID 417572)
-- Name: thematic_surface them_surface_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5185 (class 2606 OID 417542)
-- Name: thematic_surface them_surface_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5187 (class 2606 OID 417552)
-- Name: thematic_surface them_surface_room_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_room_fk FOREIGN KEY (room_id) REFERENCES citydb.room(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5206 (class 2606 OID 417647)
-- Name: tin_relief tin_relief_comp_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tin_relief
    ADD CONSTRAINT tin_relief_comp_fk FOREIGN KEY (id) REFERENCES citydb.relief_component(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5207 (class 2606 OID 417652)
-- Name: tin_relief tin_relief_geom_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tin_relief
    ADD CONSTRAINT tin_relief_geom_fk FOREIGN KEY (surface_geometry_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5208 (class 2606 OID 417657)
-- Name: tin_relief tin_relief_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tin_relief
    ADD CONSTRAINT tin_relief_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5215 (class 2606 OID 417692)
-- Name: traffic_area traffic_area_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.traffic_area
    ADD CONSTRAINT traffic_area_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5217 (class 2606 OID 417702)
-- Name: traffic_area traffic_area_lod2msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.traffic_area
    ADD CONSTRAINT traffic_area_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5218 (class 2606 OID 417707)
-- Name: traffic_area traffic_area_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.traffic_area
    ADD CONSTRAINT traffic_area_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5219 (class 2606 OID 417712)
-- Name: traffic_area traffic_area_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.traffic_area
    ADD CONSTRAINT traffic_area_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5216 (class 2606 OID 417697)
-- Name: traffic_area traffic_area_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.traffic_area
    ADD CONSTRAINT traffic_area_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5220 (class 2606 OID 417717)
-- Name: traffic_area traffic_area_trancmplx_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.traffic_area
    ADD CONSTRAINT traffic_area_trancmplx_fk FOREIGN KEY (transportation_complex_id) REFERENCES citydb.transportation_complex(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5210 (class 2606 OID 417667)
-- Name: transportation_complex tran_complex_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.transportation_complex
    ADD CONSTRAINT tran_complex_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5211 (class 2606 OID 417672)
-- Name: transportation_complex tran_complex_lod1msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.transportation_complex
    ADD CONSTRAINT tran_complex_lod1msrf_fk FOREIGN KEY (lod1_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5212 (class 2606 OID 417677)
-- Name: transportation_complex tran_complex_lod2msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.transportation_complex
    ADD CONSTRAINT tran_complex_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5213 (class 2606 OID 417682)
-- Name: transportation_complex tran_complex_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.transportation_complex
    ADD CONSTRAINT tran_complex_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5214 (class 2606 OID 417687)
-- Name: transportation_complex tran_complex_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.transportation_complex
    ADD CONSTRAINT tran_complex_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5209 (class 2606 OID 417662)
-- Name: transportation_complex tran_complex_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.transportation_complex
    ADD CONSTRAINT tran_complex_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5280 (class 2606 OID 418017)
-- Name: tunnel_hollow_space tun_hspace_cityobj_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_hollow_space
    ADD CONSTRAINT tun_hspace_cityobj_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5282 (class 2606 OID 418027)
-- Name: tunnel_hollow_space tun_hspace_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_hollow_space
    ADD CONSTRAINT tun_hspace_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5283 (class 2606 OID 418032)
-- Name: tunnel_hollow_space tun_hspace_lod4solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_hollow_space
    ADD CONSTRAINT tun_hspace_lod4solid_fk FOREIGN KEY (lod4_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5284 (class 2606 OID 418037)
-- Name: tunnel_hollow_space tun_hspace_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_hollow_space
    ADD CONSTRAINT tun_hspace_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5281 (class 2606 OID 418022)
-- Name: tunnel_hollow_space tun_hspace_tunnel_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_hollow_space
    ADD CONSTRAINT tun_hspace_tunnel_fk FOREIGN KEY (tunnel_id) REFERENCES citydb.tunnel(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5278 (class 2606 OID 418007)
-- Name: tunnel_open_to_them_srf tun_open_to_them_srf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_open_to_them_srf
    ADD CONSTRAINT tun_open_to_them_srf_fk FOREIGN KEY (tunnel_opening_id) REFERENCES citydb.tunnel_opening(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5279 (class 2606 OID 418012)
-- Name: tunnel_open_to_them_srf tun_open_to_them_srf_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_open_to_them_srf
    ADD CONSTRAINT tun_open_to_them_srf_fk1 FOREIGN KEY (tunnel_thematic_surface_id) REFERENCES citydb.tunnel_thematic_surface(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5285 (class 2606 OID 418042)
-- Name: tunnel_thematic_surface tun_them_srf_cityobj_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_cityobj_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5288 (class 2606 OID 418057)
-- Name: tunnel_thematic_surface tun_them_srf_hspace_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_hspace_fk FOREIGN KEY (tunnel_hollow_space_id) REFERENCES citydb.tunnel_hollow_space(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5290 (class 2606 OID 418067)
-- Name: tunnel_thematic_surface tun_them_srf_lod2msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5291 (class 2606 OID 418072)
-- Name: tunnel_thematic_surface tun_them_srf_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5292 (class 2606 OID 418077)
-- Name: tunnel_thematic_surface tun_them_srf_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5286 (class 2606 OID 418047)
-- Name: tunnel_thematic_surface tun_them_srf_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5289 (class 2606 OID 418062)
-- Name: tunnel_thematic_surface tun_them_srf_tun_inst_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_tun_inst_fk FOREIGN KEY (tunnel_installation_id) REFERENCES citydb.tunnel_installation(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5287 (class 2606 OID 418052)
-- Name: tunnel_thematic_surface tun_them_srf_tunnel_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_tunnel_fk FOREIGN KEY (tunnel_id) REFERENCES citydb.tunnel(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5266 (class 2606 OID 417947)
-- Name: tunnel tunnel_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5309 (class 2606 OID 418162)
-- Name: tunnel_furniture tunnel_furn_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_furniture
    ADD CONSTRAINT tunnel_furn_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5310 (class 2606 OID 418167)
-- Name: tunnel_furniture tunnel_furn_hspace_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_furniture
    ADD CONSTRAINT tunnel_furn_hspace_fk FOREIGN KEY (tunnel_hollow_space_id) REFERENCES citydb.tunnel_hollow_space(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5311 (class 2606 OID 418172)
-- Name: tunnel_furniture tunnel_furn_lod4brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_furniture
    ADD CONSTRAINT tunnel_furn_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5312 (class 2606 OID 418177)
-- Name: tunnel_furniture tunnel_furn_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_furniture
    ADD CONSTRAINT tunnel_furn_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5313 (class 2606 OID 418182)
-- Name: tunnel_furniture tunnel_furn_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_furniture
    ADD CONSTRAINT tunnel_furn_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5299 (class 2606 OID 418112)
-- Name: tunnel_installation tunnel_inst_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5302 (class 2606 OID 418127)
-- Name: tunnel_installation tunnel_inst_hspace_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_hspace_fk FOREIGN KEY (tunnel_hollow_space_id) REFERENCES citydb.tunnel_hollow_space(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5303 (class 2606 OID 418132)
-- Name: tunnel_installation tunnel_inst_lod2brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_lod2brep_fk FOREIGN KEY (lod2_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5306 (class 2606 OID 418147)
-- Name: tunnel_installation tunnel_inst_lod2impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_lod2impl_fk FOREIGN KEY (lod2_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5304 (class 2606 OID 418137)
-- Name: tunnel_installation tunnel_inst_lod3brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_lod3brep_fk FOREIGN KEY (lod3_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5307 (class 2606 OID 418152)
-- Name: tunnel_installation tunnel_inst_lod3impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5305 (class 2606 OID 418142)
-- Name: tunnel_installation tunnel_inst_lod4brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5308 (class 2606 OID 418157)
-- Name: tunnel_installation tunnel_inst_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5300 (class 2606 OID 418117)
-- Name: tunnel_installation tunnel_inst_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5301 (class 2606 OID 418122)
-- Name: tunnel_installation tunnel_inst_tunnel_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_tunnel_fk FOREIGN KEY (tunnel_id) REFERENCES citydb.tunnel(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5269 (class 2606 OID 417962)
-- Name: tunnel tunnel_lod1msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod1msrf_fk FOREIGN KEY (lod1_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5273 (class 2606 OID 417982)
-- Name: tunnel tunnel_lod1solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod1solid_fk FOREIGN KEY (lod1_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5270 (class 2606 OID 417967)
-- Name: tunnel tunnel_lod2msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5274 (class 2606 OID 417987)
-- Name: tunnel tunnel_lod2solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod2solid_fk FOREIGN KEY (lod2_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5271 (class 2606 OID 417972)
-- Name: tunnel tunnel_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5275 (class 2606 OID 417992)
-- Name: tunnel tunnel_lod3solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod3solid_fk FOREIGN KEY (lod3_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5272 (class 2606 OID 417977)
-- Name: tunnel tunnel_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5276 (class 2606 OID 417997)
-- Name: tunnel tunnel_lod4solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod4solid_fk FOREIGN KEY (lod4_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5277 (class 2606 OID 418002)
-- Name: tunnel tunnel_objectclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_objectclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5293 (class 2606 OID 418082)
-- Name: tunnel_opening tunnel_open_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_opening
    ADD CONSTRAINT tunnel_open_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5297 (class 2606 OID 418102)
-- Name: tunnel_opening tunnel_open_lod3impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_opening
    ADD CONSTRAINT tunnel_open_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5295 (class 2606 OID 418092)
-- Name: tunnel_opening tunnel_open_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_opening
    ADD CONSTRAINT tunnel_open_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5298 (class 2606 OID 418107)
-- Name: tunnel_opening tunnel_open_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_opening
    ADD CONSTRAINT tunnel_open_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5296 (class 2606 OID 418097)
-- Name: tunnel_opening tunnel_open_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_opening
    ADD CONSTRAINT tunnel_open_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5294 (class 2606 OID 418087)
-- Name: tunnel_opening tunnel_open_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_opening
    ADD CONSTRAINT tunnel_open_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5267 (class 2606 OID 417952)
-- Name: tunnel tunnel_parent_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_parent_fk FOREIGN KEY (tunnel_parent_id) REFERENCES citydb.tunnel(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5268 (class 2606 OID 417957)
-- Name: tunnel tunnel_root_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_root_fk FOREIGN KEY (tunnel_root_id) REFERENCES citydb.tunnel(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5258 (class 2606 OID 417907)
-- Name: waterboundary_surface waterbnd_srf_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterboundary_surface
    ADD CONSTRAINT waterbnd_srf_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5260 (class 2606 OID 417917)
-- Name: waterboundary_surface waterbnd_srf_lod2srf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterboundary_surface
    ADD CONSTRAINT waterbnd_srf_lod2srf_fk FOREIGN KEY (lod2_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5261 (class 2606 OID 417922)
-- Name: waterboundary_surface waterbnd_srf_lod3srf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterboundary_surface
    ADD CONSTRAINT waterbnd_srf_lod3srf_fk FOREIGN KEY (lod3_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5262 (class 2606 OID 417927)
-- Name: waterboundary_surface waterbnd_srf_lod4srf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterboundary_surface
    ADD CONSTRAINT waterbnd_srf_lod4srf_fk FOREIGN KEY (lod4_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5259 (class 2606 OID 417912)
-- Name: waterboundary_surface waterbnd_srf_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterboundary_surface
    ADD CONSTRAINT waterbnd_srf_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5256 (class 2606 OID 417897)
-- Name: waterbod_to_waterbnd_srf waterbod_to_waterbnd_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbod_to_waterbnd_srf
    ADD CONSTRAINT waterbod_to_waterbnd_fk FOREIGN KEY (waterboundary_surface_id) REFERENCES citydb.waterboundary_surface(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5257 (class 2606 OID 417902)
-- Name: waterbod_to_waterbnd_srf waterbod_to_waterbnd_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbod_to_waterbnd_srf
    ADD CONSTRAINT waterbod_to_waterbnd_fk1 FOREIGN KEY (waterbody_id) REFERENCES citydb.waterbody(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5248 (class 2606 OID 417857)
-- Name: waterbody waterbody_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5249 (class 2606 OID 417862)
-- Name: waterbody waterbody_lod0msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_lod0msrf_fk FOREIGN KEY (lod0_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5250 (class 2606 OID 417867)
-- Name: waterbody waterbody_lod1msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_lod1msrf_fk FOREIGN KEY (lod1_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5251 (class 2606 OID 417872)
-- Name: waterbody waterbody_lod1solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_lod1solid_fk FOREIGN KEY (lod1_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5252 (class 2606 OID 417877)
-- Name: waterbody waterbody_lod2solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_lod2solid_fk FOREIGN KEY (lod2_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5253 (class 2606 OID 417882)
-- Name: waterbody waterbody_lod3solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_lod3solid_fk FOREIGN KEY (lod3_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5254 (class 2606 OID 417887)
-- Name: waterbody waterbody_lod4solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_lod4solid_fk FOREIGN KEY (lod4_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5255 (class 2606 OID 417892)
-- Name: waterbody waterbody_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


-- Completed on 2021-09-13 14:09:54

--
-- PostgreSQL database dump complete
--


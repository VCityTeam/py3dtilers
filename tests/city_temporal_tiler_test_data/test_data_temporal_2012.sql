--
-- PostgreSQL database dump
--

-- Dumped from database version 14.2
-- Dumped by pg_dump version 14.2

-- Started on 2022-03-24 16:28:00

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 7 (class 2615 OID 31292)
-- Name: citydb; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA citydb;


ALTER SCHEMA citydb OWNER TO postgres;

--
-- TOC entry 8 (class 2615 OID 31293)
-- Name: citydb_pkg; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA citydb_pkg;


ALTER SCHEMA citydb_pkg OWNER TO postgres;

--
-- TOC entry 2 (class 3079 OID 31294)
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;




--
-- TOC entry 2363 (class 1247 OID 32884)
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
-- TOC entry 1512 (class 1255 OID 32885)
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
-- TOC entry 1513 (class 1255 OID 32886)
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
-- TOC entry 1514 (class 1255 OID 32887)
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
-- TOC entry 1515 (class 1255 OID 32888)
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
-- TOC entry 1516 (class 1255 OID 32889)
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
-- TOC entry 1517 (class 1255 OID 32890)
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
-- TOC entry 1518 (class 1255 OID 32891)
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
-- TOC entry 1519 (class 1255 OID 32892)
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
-- TOC entry 1520 (class 1255 OID 32893)
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
-- TOC entry 1521 (class 1255 OID 32894)
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
-- TOC entry 1522 (class 1255 OID 32895)
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
-- TOC entry 1523 (class 1255 OID 32896)
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
-- TOC entry 1524 (class 1255 OID 32897)
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
-- TOC entry 1525 (class 1255 OID 32898)
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
-- TOC entry 1526 (class 1255 OID 32899)
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
-- TOC entry 1527 (class 1255 OID 32900)
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
-- TOC entry 1528 (class 1255 OID 32901)
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
-- TOC entry 1529 (class 1255 OID 32902)
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
-- TOC entry 1530 (class 1255 OID 32903)
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
-- TOC entry 1531 (class 1255 OID 32904)
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
-- TOC entry 1532 (class 1255 OID 32905)
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
-- TOC entry 1533 (class 1255 OID 32906)
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
-- TOC entry 1534 (class 1255 OID 32907)
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
-- TOC entry 1535 (class 1255 OID 32908)
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
-- TOC entry 1536 (class 1255 OID 32909)
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
-- TOC entry 1537 (class 1255 OID 32910)
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
-- TOC entry 1538 (class 1255 OID 32911)
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
-- TOC entry 1539 (class 1255 OID 32912)
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
-- TOC entry 1540 (class 1255 OID 32913)
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
-- TOC entry 1541 (class 1255 OID 32914)
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
-- TOC entry 1542 (class 1255 OID 32915)
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
-- TOC entry 1543 (class 1255 OID 32916)
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
-- TOC entry 1544 (class 1255 OID 32917)
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
-- TOC entry 1545 (class 1255 OID 32918)
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
-- TOC entry 1546 (class 1255 OID 32919)
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
-- TOC entry 1547 (class 1255 OID 32920)
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
-- TOC entry 1548 (class 1255 OID 32922)
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
-- TOC entry 1549 (class 1255 OID 32923)
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
-- TOC entry 1550 (class 1255 OID 32924)
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
-- TOC entry 1551 (class 1255 OID 32925)
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
-- TOC entry 1552 (class 1255 OID 32926)
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
-- TOC entry 1553 (class 1255 OID 32927)
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
-- TOC entry 1554 (class 1255 OID 32928)
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
-- TOC entry 1555 (class 1255 OID 32929)
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
-- TOC entry 1556 (class 1255 OID 32930)
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
-- TOC entry 1557 (class 1255 OID 32931)
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
-- TOC entry 1558 (class 1255 OID 32932)
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
-- TOC entry 1559 (class 1255 OID 32933)
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
-- TOC entry 1560 (class 1255 OID 32934)
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
-- TOC entry 1561 (class 1255 OID 32935)
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
-- TOC entry 1562 (class 1255 OID 32936)
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
-- TOC entry 1563 (class 1255 OID 32937)
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
-- TOC entry 1564 (class 1255 OID 32938)
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
-- TOC entry 1565 (class 1255 OID 32939)
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
-- TOC entry 1566 (class 1255 OID 32940)
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
-- TOC entry 1567 (class 1255 OID 32941)
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
-- TOC entry 1568 (class 1255 OID 32942)
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
-- TOC entry 1569 (class 1255 OID 32943)
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
-- TOC entry 1570 (class 1255 OID 32944)
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
-- TOC entry 1571 (class 1255 OID 32945)
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
-- TOC entry 1572 (class 1255 OID 32946)
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
-- TOC entry 1573 (class 1255 OID 32947)
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
-- TOC entry 1574 (class 1255 OID 32948)
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
-- TOC entry 1575 (class 1255 OID 32949)
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
-- TOC entry 1576 (class 1255 OID 32950)
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
-- TOC entry 1577 (class 1255 OID 32951)
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
-- TOC entry 1578 (class 1255 OID 32952)
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
-- TOC entry 1579 (class 1255 OID 32953)
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
-- TOC entry 1580 (class 1255 OID 32954)
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
-- TOC entry 1581 (class 1255 OID 32955)
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
-- TOC entry 1582 (class 1255 OID 32956)
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
-- TOC entry 1583 (class 1255 OID 32957)
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
-- TOC entry 1584 (class 1255 OID 32958)
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
-- TOC entry 1585 (class 1255 OID 32959)
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
-- TOC entry 1586 (class 1255 OID 32960)
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
-- TOC entry 1587 (class 1255 OID 32961)
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
-- TOC entry 1588 (class 1255 OID 32962)
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
-- TOC entry 1589 (class 1255 OID 32963)
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
-- TOC entry 1590 (class 1255 OID 32964)
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
-- TOC entry 1591 (class 1255 OID 32965)
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
-- TOC entry 1592 (class 1255 OID 32966)
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
-- TOC entry 1593 (class 1255 OID 32967)
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
-- TOC entry 1594 (class 1255 OID 32968)
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
-- TOC entry 1595 (class 1255 OID 32969)
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
-- TOC entry 1596 (class 1255 OID 32970)
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
-- TOC entry 1597 (class 1255 OID 32971)
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
-- TOC entry 1598 (class 1255 OID 32972)
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
-- TOC entry 1599 (class 1255 OID 32973)
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
-- TOC entry 1600 (class 1255 OID 32974)
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
-- TOC entry 1601 (class 1255 OID 32975)
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
-- TOC entry 1602 (class 1255 OID 32976)
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
-- TOC entry 1603 (class 1255 OID 32977)
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
-- TOC entry 1604 (class 1255 OID 32978)
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
-- TOC entry 1605 (class 1255 OID 32979)
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
-- TOC entry 1606 (class 1255 OID 32980)
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
-- TOC entry 1607 (class 1255 OID 32981)
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
-- TOC entry 1608 (class 1255 OID 32982)
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
-- TOC entry 1609 (class 1255 OID 32983)
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
-- TOC entry 1610 (class 1255 OID 32984)
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
-- TOC entry 1611 (class 1255 OID 32985)
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
-- TOC entry 1612 (class 1255 OID 32986)
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
-- TOC entry 1613 (class 1255 OID 32987)
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
-- TOC entry 1614 (class 1255 OID 32988)
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
-- TOC entry 1615 (class 1255 OID 32989)
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
-- TOC entry 1616 (class 1255 OID 32990)
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
-- TOC entry 1617 (class 1255 OID 32991)
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
-- TOC entry 1618 (class 1255 OID 32992)
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
-- TOC entry 1619 (class 1255 OID 32993)
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
-- TOC entry 1620 (class 1255 OID 32994)
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
-- TOC entry 1621 (class 1255 OID 32995)
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
-- TOC entry 1622 (class 1255 OID 32996)
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
-- TOC entry 1623 (class 1255 OID 32997)
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
-- TOC entry 1624 (class 1255 OID 32998)
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
-- TOC entry 1625 (class 1255 OID 33000)
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
-- TOC entry 1626 (class 1255 OID 33001)
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
-- TOC entry 1627 (class 1255 OID 33002)
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
-- TOC entry 1628 (class 1255 OID 33003)
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
-- TOC entry 1629 (class 1255 OID 33004)
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
-- TOC entry 1630 (class 1255 OID 33005)
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
-- TOC entry 1631 (class 1255 OID 33006)
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
-- TOC entry 1632 (class 1255 OID 33007)
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
-- TOC entry 1633 (class 1255 OID 33008)
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
-- TOC entry 1634 (class 1255 OID 33009)
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
-- TOC entry 1635 (class 1255 OID 33010)
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
-- TOC entry 1636 (class 1255 OID 33011)
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
-- TOC entry 1637 (class 1255 OID 33012)
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
-- TOC entry 1638 (class 1255 OID 33013)
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
-- TOC entry 1639 (class 1255 OID 33014)
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
-- TOC entry 1640 (class 1255 OID 33015)
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
-- TOC entry 1641 (class 1255 OID 33016)
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
-- TOC entry 1642 (class 1255 OID 33017)
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
-- TOC entry 1643 (class 1255 OID 33018)
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
-- TOC entry 1644 (class 1255 OID 33019)
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
-- TOC entry 1645 (class 1255 OID 33020)
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
-- TOC entry 1646 (class 1255 OID 33021)
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
-- TOC entry 1647 (class 1255 OID 33022)
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
-- TOC entry 1648 (class 1255 OID 33023)
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
-- TOC entry 1649 (class 1255 OID 33024)
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
-- TOC entry 1650 (class 1255 OID 33025)
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
-- TOC entry 1651 (class 1255 OID 33026)
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
-- TOC entry 1652 (class 1255 OID 33027)
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
-- TOC entry 1653 (class 1255 OID 33028)
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
-- TOC entry 1654 (class 1255 OID 33029)
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
-- TOC entry 1655 (class 1255 OID 33030)
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
-- TOC entry 1656 (class 1255 OID 33031)
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
-- TOC entry 1657 (class 1255 OID 33032)
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
-- TOC entry 1658 (class 1255 OID 33033)
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
-- TOC entry 1659 (class 1255 OID 33034)
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
-- TOC entry 1660 (class 1255 OID 33035)
-- Name: construct_normal(text, text, text, integer); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.construct_normal(ind_name text, tab_name text, att_name text, crs integer DEFAULT 0) RETURNS citydb_pkg.index_obj
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
SELECT ($1, $2, $3, 0, $4, 0)::citydb_pkg.INDEX_OBJ;
$_$;


ALTER FUNCTION citydb_pkg.construct_normal(ind_name text, tab_name text, att_name text, crs integer) OWNER TO postgres;

--
-- TOC entry 1661 (class 1255 OID 33036)
-- Name: construct_spatial_2d(text, text, text, integer); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.construct_spatial_2d(ind_name text, tab_name text, att_name text, crs integer DEFAULT 0) RETURNS citydb_pkg.index_obj
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
SELECT ($1, $2, $3, 1, $4, 0)::citydb_pkg.INDEX_OBJ;
$_$;


ALTER FUNCTION citydb_pkg.construct_spatial_2d(ind_name text, tab_name text, att_name text, crs integer) OWNER TO postgres;

--
-- TOC entry 1662 (class 1255 OID 33037)
-- Name: construct_spatial_3d(text, text, text, integer); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.construct_spatial_3d(ind_name text, tab_name text, att_name text, crs integer DEFAULT 0) RETURNS citydb_pkg.index_obj
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
SELECT ($1, $2, $3, 1, $4, 1)::citydb_pkg.INDEX_OBJ;
$_$;


ALTER FUNCTION citydb_pkg.construct_spatial_3d(ind_name text, tab_name text, att_name text, crs integer) OWNER TO postgres;

--
-- TOC entry 1663 (class 1255 OID 33038)
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
-- TOC entry 1664 (class 1255 OID 33039)
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
-- TOC entry 1665 (class 1255 OID 33040)
-- Name: create_normal_indexes(text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.create_normal_indexes(schema_name text DEFAULT 'citydb'::text) RETURNS text[]
    LANGUAGE sql STRICT
    AS $_$
SELECT citydb_pkg.create_indexes(0, $1);
$_$;


ALTER FUNCTION citydb_pkg.create_normal_indexes(schema_name text) OWNER TO postgres;

--
-- TOC entry 1666 (class 1255 OID 33041)
-- Name: create_spatial_indexes(text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.create_spatial_indexes(schema_name text DEFAULT 'citydb'::text) RETURNS text[]
    LANGUAGE sql STRICT
    AS $_$
SELECT citydb_pkg.create_indexes(1, $1);
$_$;


ALTER FUNCTION citydb_pkg.create_spatial_indexes(schema_name text) OWNER TO postgres;

--
-- TOC entry 1667 (class 1255 OID 33042)
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
-- TOC entry 1668 (class 1255 OID 33043)
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
-- TOC entry 1669 (class 1255 OID 33044)
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
-- TOC entry 1670 (class 1255 OID 33045)
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
-- TOC entry 1671 (class 1255 OID 33046)
-- Name: drop_normal_indexes(text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.drop_normal_indexes(schema_name text DEFAULT 'citydb'::text) RETURNS text[]
    LANGUAGE sql STRICT
    AS $_$
SELECT citydb_pkg.drop_indexes(0, $1); 
$_$;


ALTER FUNCTION citydb_pkg.drop_normal_indexes(schema_name text) OWNER TO postgres;

--
-- TOC entry 1672 (class 1255 OID 33047)
-- Name: drop_spatial_indexes(text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.drop_spatial_indexes(schema_name text DEFAULT 'citydb'::text) RETURNS text[]
    LANGUAGE sql STRICT
    AS $_$
SELECT citydb_pkg.drop_indexes(1, $1);
$_$;


ALTER FUNCTION citydb_pkg.drop_spatial_indexes(schema_name text) OWNER TO postgres;

--
-- TOC entry 1673 (class 1255 OID 33048)
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
-- TOC entry 1674 (class 1255 OID 33049)
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
-- TOC entry 1675 (class 1255 OID 33050)
-- Name: get_seq_values(text, integer); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.get_seq_values(seq_name text, seq_count integer) RETURNS SETOF integer
    LANGUAGE sql STRICT
    AS $_$
SELECT nextval($1)::int FROM generate_series(1, $2);
$_$;


ALTER FUNCTION citydb_pkg.get_seq_values(seq_name text, seq_count integer) OWNER TO postgres;

--
-- TOC entry 1676 (class 1255 OID 33051)
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
-- TOC entry 1677 (class 1255 OID 33052)
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
-- TOC entry 1678 (class 1255 OID 33053)
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
-- TOC entry 1679 (class 1255 OID 33054)
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
-- TOC entry 1680 (class 1255 OID 33055)
-- Name: min(numeric, numeric); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.min(a numeric, b numeric) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    AS $_$
SELECT LEAST($1,$2);
$_$;


ALTER FUNCTION citydb_pkg.min(a numeric, b numeric) OWNER TO postgres;

--
-- TOC entry 1681 (class 1255 OID 33056)
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
-- TOC entry 1682 (class 1255 OID 33057)
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
-- TOC entry 1683 (class 1255 OID 33058)
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
-- TOC entry 1684 (class 1255 OID 33059)
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
-- TOC entry 1685 (class 1255 OID 33060)
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
-- TOC entry 1686 (class 1255 OID 33061)
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
-- TOC entry 1687 (class 1255 OID 33062)
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
-- TOC entry 1688 (class 1255 OID 33063)
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
-- TOC entry 1689 (class 1255 OID 33064)
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
-- TOC entry 1690 (class 1255 OID 33065)
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
-- TOC entry 1691 (class 1255 OID 33066)
-- Name: versioning_db(text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.versioning_db(schema_name text DEFAULT 'citydb'::text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT 'OFF'::text;
$$;


ALTER FUNCTION citydb_pkg.versioning_db(schema_name text) OWNER TO postgres;

--
-- TOC entry 1692 (class 1255 OID 33067)
-- Name: versioning_table(text, text); Type: FUNCTION; Schema: citydb_pkg; Owner: postgres
--

CREATE FUNCTION citydb_pkg.versioning_table(table_name text, schema_name text DEFAULT 'citydb'::text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT 'OFF'::text;
$$;


ALTER FUNCTION citydb_pkg.versioning_table(table_name text, schema_name text) OWNER TO postgres;

--
-- TOC entry 229 (class 1259 OID 33068)
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


--
-- TOC entry 230 (class 1259 OID 33069)
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
-- TOC entry 231 (class 1259 OID 33075)
-- Name: address_to_bridge; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.address_to_bridge (
    bridge_id integer NOT NULL,
    address_id integer NOT NULL
);


ALTER TABLE citydb.address_to_bridge OWNER TO postgres;

--
-- TOC entry 232 (class 1259 OID 33078)
-- Name: address_to_building; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.address_to_building (
    building_id integer NOT NULL,
    address_id integer NOT NULL
);


ALTER TABLE citydb.address_to_building OWNER TO postgres;

--
-- TOC entry 233 (class 1259 OID 33081)
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
-- TOC entry 234 (class 1259 OID 33082)
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
-- TOC entry 235 (class 1259 OID 33088)
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
-- TOC entry 236 (class 1259 OID 33093)
-- Name: appear_to_surface_data; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.appear_to_surface_data (
    surface_data_id integer NOT NULL,
    appearance_id integer NOT NULL
);


ALTER TABLE citydb.appear_to_surface_data OWNER TO postgres;

--
-- TOC entry 237 (class 1259 OID 33096)
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
-- TOC entry 238 (class 1259 OID 33097)
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
-- TOC entry 239 (class 1259 OID 33105)
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
-- TOC entry 240 (class 1259 OID 33110)
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
-- TOC entry 241 (class 1259 OID 33115)
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
-- TOC entry 242 (class 1259 OID 33120)
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
-- TOC entry 243 (class 1259 OID 33125)
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
-- TOC entry 244 (class 1259 OID 33130)
-- Name: bridge_open_to_them_srf; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.bridge_open_to_them_srf (
    bridge_opening_id integer NOT NULL,
    bridge_thematic_surface_id integer NOT NULL
);


ALTER TABLE citydb.bridge_open_to_them_srf OWNER TO postgres;

--
-- TOC entry 245 (class 1259 OID 33133)
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
-- TOC entry 246 (class 1259 OID 33138)
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
-- TOC entry 247 (class 1259 OID 33143)
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
-- TOC entry 248 (class 1259 OID 33146)
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
-- TOC entry 249 (class 1259 OID 33151)
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
-- TOC entry 250 (class 1259 OID 33156)
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
-- TOC entry 251 (class 1259 OID 33161)
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
-- TOC entry 252 (class 1259 OID 33166)
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
-- TOC entry 253 (class 1259 OID 33167)
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
-- TOC entry 254 (class 1259 OID 33173)
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
-- TOC entry 255 (class 1259 OID 33174)
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
-- TOC entry 256 (class 1259 OID 33180)
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
-- TOC entry 257 (class 1259 OID 33181)
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
-- TOC entry 258 (class 1259 OID 33187)
-- Name: cityobject_member; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.cityobject_member (
    citymodel_id integer NOT NULL,
    cityobject_id integer NOT NULL
);


ALTER TABLE citydb.cityobject_member OWNER TO postgres;

--
-- TOC entry 259 (class 1259 OID 33190)
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
-- TOC entry 260 (class 1259 OID 33195)
-- Name: database_srs; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.database_srs (
    srid integer NOT NULL,
    gml_srs_name character varying(1000)
);


ALTER TABLE citydb.database_srs OWNER TO postgres;

--
-- TOC entry 261 (class 1259 OID 33200)
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
-- TOC entry 262 (class 1259 OID 33201)
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
-- TOC entry 263 (class 1259 OID 33207)
-- Name: generalization; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.generalization (
    cityobject_id integer NOT NULL,
    generalizes_to_id integer NOT NULL
);


ALTER TABLE citydb.generalization OWNER TO postgres;

--
-- TOC entry 264 (class 1259 OID 33210)
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
-- TOC entry 265 (class 1259 OID 33215)
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
-- TOC entry 266 (class 1259 OID 33216)
-- Name: grid_coverage; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.grid_coverage (
    id integer DEFAULT nextval('citydb.grid_coverage_seq'::regclass) NOT NULL,
    rasterproperty public.raster
);


ALTER TABLE citydb.grid_coverage OWNER TO postgres;

--
-- TOC entry 267 (class 1259 OID 33222)
-- Name: group_to_cityobject; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.group_to_cityobject (
    cityobject_id integer NOT NULL,
    cityobjectgroup_id integer NOT NULL,
    role character varying(256)
);


ALTER TABLE citydb.group_to_cityobject OWNER TO postgres;

--
-- TOC entry 268 (class 1259 OID 33225)
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
-- TOC entry 269 (class 1259 OID 33226)
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
-- TOC entry 270 (class 1259 OID 33232)
-- Name: index_table; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.index_table (
    id integer NOT NULL,
    obj citydb_pkg.index_obj
);


ALTER TABLE citydb.index_table OWNER TO postgres;

--
-- TOC entry 271 (class 1259 OID 33237)
-- Name: index_table_id_seq; Type: SEQUENCE; Schema: citydb; Owner: postgres
--

CREATE SEQUENCE citydb.index_table_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE citydb.index_table_id_seq OWNER TO postgres;

--
-- TOC entry 6124 (class 0 OID 0)
-- Dependencies: 271
-- Name: index_table_id_seq; Type: SEQUENCE OWNED BY; Schema: citydb; Owner: postgres
--

ALTER SEQUENCE citydb.index_table_id_seq OWNED BY citydb.index_table.id;


--
-- TOC entry 272 (class 1259 OID 33239)
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
-- TOC entry 273 (class 1259 OID 33244)
-- Name: masspoint_relief; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.masspoint_relief (
    id integer NOT NULL,
    objectclass_id integer NOT NULL,
    relief_points public.geometry(MultiPointZ,3946)
);


ALTER TABLE citydb.masspoint_relief OWNER TO postgres;

--
-- TOC entry 274 (class 1259 OID 33249)
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
-- TOC entry 275 (class 1259 OID 33254)
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
-- TOC entry 276 (class 1259 OID 33259)
-- Name: opening_to_them_surface; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.opening_to_them_surface (
    opening_id integer NOT NULL,
    thematic_surface_id integer NOT NULL
);


ALTER TABLE citydb.opening_to_them_surface OWNER TO postgres;

--
-- TOC entry 277 (class 1259 OID 33262)
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
-- TOC entry 278 (class 1259 OID 33267)
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
-- TOC entry 279 (class 1259 OID 33272)
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
-- TOC entry 280 (class 1259 OID 33278)
-- Name: relief_feat_to_rel_comp; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.relief_feat_to_rel_comp (
    relief_component_id integer NOT NULL,
    relief_feature_id integer NOT NULL
);


ALTER TABLE citydb.relief_feat_to_rel_comp OWNER TO postgres;

--
-- TOC entry 281 (class 1259 OID 33281)
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
-- TOC entry 282 (class 1259 OID 33287)
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
-- TOC entry 283 (class 1259 OID 33292)
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
-- TOC entry 284 (class 1259 OID 33293)
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
-- TOC entry 285 (class 1259 OID 33299)
-- Name: schema_referencing; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.schema_referencing (
    referencing_id integer NOT NULL,
    referenced_id integer NOT NULL
);


ALTER TABLE citydb.schema_referencing OWNER TO postgres;

--
-- TOC entry 286 (class 1259 OID 33302)
-- Name: schema_to_objectclass; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.schema_to_objectclass (
    schema_id integer NOT NULL,
    objectclass_id integer NOT NULL
);


ALTER TABLE citydb.schema_to_objectclass OWNER TO postgres;

--
-- TOC entry 287 (class 1259 OID 33305)
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
-- TOC entry 288 (class 1259 OID 33313)
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
-- TOC entry 289 (class 1259 OID 33317)
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
-- TOC entry 290 (class 1259 OID 33323)
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
-- TOC entry 291 (class 1259 OID 33324)
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
-- TOC entry 292 (class 1259 OID 33330)
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
-- TOC entry 293 (class 1259 OID 33331)
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
-- TOC entry 294 (class 1259 OID 33337)
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
-- TOC entry 295 (class 1259 OID 33342)
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
-- TOC entry 296 (class 1259 OID 33345)
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
-- TOC entry 297 (class 1259 OID 33350)
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
-- TOC entry 298 (class 1259 OID 33355)
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
-- TOC entry 299 (class 1259 OID 33360)
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
-- TOC entry 300 (class 1259 OID 33365)
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
-- TOC entry 301 (class 1259 OID 33370)
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
-- TOC entry 302 (class 1259 OID 33375)
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
-- TOC entry 303 (class 1259 OID 33380)
-- Name: tunnel_open_to_them_srf; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.tunnel_open_to_them_srf (
    tunnel_opening_id integer NOT NULL,
    tunnel_thematic_surface_id integer NOT NULL
);


ALTER TABLE citydb.tunnel_open_to_them_srf OWNER TO postgres;

--
-- TOC entry 304 (class 1259 OID 33383)
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
-- TOC entry 305 (class 1259 OID 33388)
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
-- TOC entry 306 (class 1259 OID 33391)
-- Name: waterbod_to_waterbnd_srf; Type: TABLE; Schema: citydb; Owner: postgres
--

CREATE TABLE citydb.waterbod_to_waterbnd_srf (
    waterboundary_surface_id integer NOT NULL,
    waterbody_id integer NOT NULL
);


ALTER TABLE citydb.waterbod_to_waterbnd_srf OWNER TO postgres;

--
-- TOC entry 307 (class 1259 OID 33394)
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
-- TOC entry 308 (class 1259 OID 33399)
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
-- TOC entry 5075 (class 2604 OID 33404)
-- Name: index_table id; Type: DEFAULT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.index_table ALTER COLUMN id SET DEFAULT nextval('citydb.index_table_id_seq'::regclass);


--
-- TOC entry 6040 (class 0 OID 33069)
-- Dependencies: 230
-- Data for Name: address; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6041 (class 0 OID 33075)
-- Dependencies: 231
-- Data for Name: address_to_bridge; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6042 (class 0 OID 33078)
-- Dependencies: 232
-- Data for Name: address_to_building; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6044 (class 0 OID 33082)
-- Dependencies: 234
-- Data for Name: ade; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6045 (class 0 OID 33088)
-- Dependencies: 235
-- Data for Name: aggregation_info; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (3, 57, 'cityobject_member', 0, NULL, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (110, 3, 'cityobject_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 108, 'root_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 108, 'parent_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 59, 'relative_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (50, 57, 'citymodel_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (50, 3, 'cityobject_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (51, 50, 'appear_to_surface_data', 0, NULL, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (109, 51, 'tex_image_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (3, 23, 'group_to_cityobject', 0, NULL, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 23, 'brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 21, 'lod1_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 21, 'lod2_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 21, 'lod3_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 21, 'lod4_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 21, 'lod1_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 21, 'lod2_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 21, 'lod3_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 21, 'lod4_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (112, 113, 'parent_genattrib_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (112, 113, 'root_genattrib_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (112, 3, 'cityobject_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 112, 'surface_geometry_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 5, 'lod0_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 5, 'lod1_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 5, 'lod2_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 5, 'lod3_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 5, 'lod4_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 5, 'lod0_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 5, 'lod1_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 5, 'lod2_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 5, 'lod3_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 5, 'lod4_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 4, 'lod0_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 4, 'lod1_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 4, 'lod2_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 4, 'lod3_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 4, 'lod4_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (15, 14, 'relief_feat_to_rel_comp', 0, NULL, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 16, 'surface_geometry_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (111, 19, 'coverage_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (47, 42, 'transportation_complex_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 47, 'lod2_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 47, 'lod3_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 47, 'lod4_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 42, 'lod1_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 42, 'lod2_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 42, 'lod3_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 42, 'lod4_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 7, 'lod1_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 7, 'lod2_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 7, 'lod3_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 7, 'lod4_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 7, 'lod1_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 7, 'lod2_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 7, 'lod3_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 7, 'lod4_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 8, 'lod1_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 8, 'lod2_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 8, 'lod3_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 8, 'lod4_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 8, 'lod1_multi_solid_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 8, 'lod2_multi_solid_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 8, 'lod3_multi_solid_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 8, 'lod4_multi_solid_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (10, 9, 'waterbod_to_waterbnd_srf', 0, NULL, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 9, 'lod0_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 9, 'lod1_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 9, 'lod1_solid_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 9, 'lod2_solid_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 9, 'lod3_solid_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 9, 'lod4_solid_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 10, 'lod2_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 10, 'lod3_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 10, 'lod4_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (58, 62, 'address_to_bridge', 0, NULL, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (58, 77, 'address_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (63, 62, 'bridge_parent_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (63, 64, 'bridge_root_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (82, 62, 'bridge_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (80, 81, 'bridge_room_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (66, 81, 'bridge_room_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (65, 62, 'bridge_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (77, 67, 'bridge_open_to_them_srf', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (81, 62, 'bridge_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (67, 81, 'bridge_room_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (67, 62, 'bridge_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (67, 65, 'bridge_installation_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 62, 'lod1_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 62, 'lod2_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 62, 'lod3_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 62, 'lod4_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 62, 'lod1_solid_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 62, 'lod2_solid_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 62, 'lod3_solid_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 62, 'lod4_solid_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 80, 'lod4_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 65, 'lod2_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 65, 'lod3_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 65, 'lod4_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 66, 'lod4_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 77, 'lod3_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 77, 'lod4_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 67, 'lod2_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 67, 'lod3_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 67, 'lod4_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 81, 'lod4_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 81, 'lod4_solid_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 82, 'lod1_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 82, 'lod2_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 82, 'lod3_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 82, 'lod4_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 80, 'lod4_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 65, 'lod2_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 65, 'lod3_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 65, 'lod4_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 66, 'lod4_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 77, 'lod3_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 77, 'lod4_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 82, 'lod1_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 82, 'lod2_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 82, 'lod3_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 82, 'lod4_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (58, 24, 'address_to_building', 0, NULL, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (58, 37, 'address_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (25, 24, 'building_parent_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (25, 26, 'building_root_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (40, 41, 'room_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (28, 41, 'room_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (27, 24, 'building_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (37, 29, 'opening_to_them_surface', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (41, 24, 'building_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (29, 41, 'room_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (29, 27, 'building_installation_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (29, 24, 'building_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 24, 'lod0_footprint_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 24, 'lod0_roofprint_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 24, 'lod1_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 24, 'lod2_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 24, 'lod3_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 24, 'lod4_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 24, 'lod1_solid_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 24, 'lod2_solid_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 24, 'lod3_solid_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 24, 'lod4_solid_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 40, 'lod4_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 27, 'lod2_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 27, 'lod3_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 27, 'lod4_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 28, 'lod4_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 37, 'lod3_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 37, 'lod4_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 29, 'lod2_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 29, 'lod3_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 29, 'lod4_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 41, 'lod4_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 41, 'lod4_solid_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 40, 'lod4_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 27, 'lod2_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 27, 'lod3_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 27, 'lod4_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 28, 'lod4_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 37, 'lod3_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 37, 'lod4_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (84, 83, 'tunnel_parent_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (84, 85, 'tunnel_root_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (101, 102, 'tunnel_hollow_space_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (87, 102, 'tunnel_hollow_space_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (86, 83, 'tunnel_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (98, 88, 'tunnel_open_to_them_srf', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (102, 83, 'tunnel_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (88, 102, 'tunnel_hollow_space_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (88, 83, 'tunnel_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (88, 86, 'tunnel_installation_id', 0, NULL, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 83, 'lod1_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 83, 'lod2_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 83, 'lod3_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 83, 'lod4_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 83, 'lod1_solid_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 83, 'lod2_solid_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 83, 'lod3_solid_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 83, 'lod4_solid_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 101, 'lod4_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 86, 'lod2_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 86, 'lod3_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 86, 'lod4_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 87, 'lod4_brep_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 98, 'lod3_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 98, 'lod4_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 88, 'lod2_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 88, 'lod3_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 88, 'lod4_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 102, 'lod4_multi_surface_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (106, 102, 'lod4_solid_id', 0, 1, 1);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 101, 'lod4_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 86, 'lod2_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 86, 'lod3_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 86, 'lod4_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 87, 'lod4_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 98, 'lod3_implicit_rep_id', 0, 1, 0);
INSERT INTO citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) VALUES (59, 98, 'lod4_implicit_rep_id', 0, 1, 0);


--
-- TOC entry 6046 (class 0 OID 33093)
-- Dependencies: 236
-- Data for Name: appear_to_surface_data; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6048 (class 0 OID 33097)
-- Dependencies: 238
-- Data for Name: appearance; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6049 (class 0 OID 33105)
-- Dependencies: 239
-- Data for Name: breakline_relief; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6050 (class 0 OID 33110)
-- Dependencies: 240
-- Data for Name: bridge; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6051 (class 0 OID 33115)
-- Dependencies: 241
-- Data for Name: bridge_constr_element; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6052 (class 0 OID 33120)
-- Dependencies: 242
-- Data for Name: bridge_furniture; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6053 (class 0 OID 33125)
-- Dependencies: 243
-- Data for Name: bridge_installation; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6054 (class 0 OID 33130)
-- Dependencies: 244
-- Data for Name: bridge_open_to_them_srf; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6055 (class 0 OID 33133)
-- Dependencies: 245
-- Data for Name: bridge_opening; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6056 (class 0 OID 33138)
-- Dependencies: 246
-- Data for Name: bridge_room; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6057 (class 0 OID 33143)
-- Dependencies: 247
-- Data for Name: bridge_thematic_surface; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6058 (class 0 OID 33146)
-- Dependencies: 248
-- Data for Name: building; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

INSERT INTO citydb.building (id, objectclass_id, building_parent_id, building_root_id, class, class_codespace, function, function_codespace, usage, usage_codespace, year_of_construction, year_of_demolition, roof_type, roof_type_codespace, measured_height, measured_height_unit, storeys_above_ground, storeys_below_ground, storey_heights_above_ground, storey_heights_ag_unit, storey_heights_below_ground, storey_heights_bg_unit, lod1_terrain_intersection, lod2_terrain_intersection, lod3_terrain_intersection, lod4_terrain_intersection, lod2_multi_curve, lod3_multi_curve, lod4_multi_curve, lod0_footprint_id, lod0_roofprint_id, lod1_multi_surface_id, lod2_multi_surface_id, lod3_multi_surface_id, lod4_multi_surface_id, lod1_solid_id, lod2_solid_id, lod3_solid_id, lod4_solid_id) VALUES (1, 26, NULL, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);


--
-- TOC entry 6059 (class 0 OID 33151)
-- Dependencies: 249
-- Data for Name: building_furniture; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6060 (class 0 OID 33156)
-- Dependencies: 250
-- Data for Name: building_installation; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6061 (class 0 OID 33161)
-- Dependencies: 251
-- Data for Name: city_furniture; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6063 (class 0 OID 33167)
-- Dependencies: 253
-- Data for Name: citymodel; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6065 (class 0 OID 33174)
-- Dependencies: 255
-- Data for Name: cityobject; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

INSERT INTO citydb.cityobject (id, objectclass_id, gmlid, gmlid_codespace, name, name_codespace, description, envelope, creation_date, termination_date, relative_to_terrain, relative_to_water, last_modification_date, updating_person, reason_for_update, lineage, xml_source) VALUES (1, 26, 'LYON_1ER_00101_0', NULL, NULL, NULL, NULL, '01030000A06A0F00000100000005000000973787C37A1E3C415B5F24FD4ABE5341516B9A779CFC67403A77BB167D1E3C415B5F24FD4ABE5341516B9A779CFC67403A77BB167D1E3C410EDAAB4B4BBE53418AADA069891B6840973787C37A1E3C410EDAAB4B4BBE53418AADA069891B6840973787C37A1E3C415B5F24FD4ABE5341516B9A779CFC6740', '2021-09-13 13:58:25.318+02', NULL, NULL, NULL, '2021-09-13 13:58:25.318+02', 'postgres', NULL, NULL, NULL);
INSERT INTO citydb.cityobject (id, objectclass_id, gmlid, gmlid_codespace, name, name_codespace, description, envelope, creation_date, termination_date, relative_to_terrain, relative_to_water, last_modification_date, updating_person, reason_for_update, lineage, xml_source) VALUES (2, 33, 'LYON_1ER_00101_0_Roof', NULL, NULL, NULL, NULL, '01030000A06A0F00000100000005000000973787C37A1E3C415B5F24FD4ABE5341516B9A779CFC67403A77BB167D1E3C415B5F24FD4ABE5341516B9A779CFC67403A77BB167D1E3C41D0436D374BBE53418AADA069891B6840973787C37A1E3C41D0436D374BBE53418AADA069891B6840973787C37A1E3C415B5F24FD4ABE5341516B9A779CFC6740', '2021-09-13 13:58:25.325+02', NULL, NULL, NULL, '2021-09-13 13:58:25.325+02', 'postgres', NULL, NULL, NULL);
INSERT INTO citydb.cityobject (id, objectclass_id, gmlid, gmlid_codespace, name, name_codespace, description, envelope, creation_date, termination_date, relative_to_terrain, relative_to_water, last_modification_date, updating_person, reason_for_update, lineage, xml_source) VALUES (3, 34, 'LYON_1ER_00101_0_Wall', NULL, NULL, NULL, NULL, '01030000A06A0F00000100000005000000973787C37A1E3C415B5F24FD4ABE5341DBF97E6ABC1668405B7A34C57A1E3C415B5F24FD4ABE5341DBF97E6ABC1668405B7A34C57A1E3C410EDAAB4B4BBE53418AADA069891B6840973787C37A1E3C410EDAAB4B4BBE53418AADA069891B6840973787C37A1E3C415B5F24FD4ABE5341DBF97E6ABC166840', '2021-09-13 13:58:25.327+02', NULL, NULL, NULL, '2021-09-13 13:58:25.327+02', 'postgres', NULL, NULL, NULL);


--
-- TOC entry 6067 (class 0 OID 33181)
-- Dependencies: 257
-- Data for Name: cityobject_genericattrib; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6068 (class 0 OID 33187)
-- Dependencies: 258
-- Data for Name: cityobject_member; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6069 (class 0 OID 33190)
-- Dependencies: 259
-- Data for Name: cityobjectgroup; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6070 (class 0 OID 33195)
-- Dependencies: 260
-- Data for Name: database_srs; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

INSERT INTO citydb.database_srs (srid, gml_srs_name) VALUES (3946, 'urn:ogc:def:crs:EPSG::3946');


--
-- TOC entry 6072 (class 0 OID 33201)
-- Dependencies: 262
-- Data for Name: external_reference; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6073 (class 0 OID 33207)
-- Dependencies: 263
-- Data for Name: generalization; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6074 (class 0 OID 33210)
-- Dependencies: 264
-- Data for Name: generic_cityobject; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6076 (class 0 OID 33216)
-- Dependencies: 266
-- Data for Name: grid_coverage; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6077 (class 0 OID 33222)
-- Dependencies: 267
-- Data for Name: group_to_cityobject; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6079 (class 0 OID 33226)
-- Dependencies: 269
-- Data for Name: implicit_geometry; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6080 (class 0 OID 33232)
-- Dependencies: 270
-- Data for Name: index_table; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

INSERT INTO citydb.index_table (id, obj) VALUES (1, '(cityobject_envelope_spx,cityobject,envelope,1,0,0)');
INSERT INTO citydb.index_table (id, obj) VALUES (2, '(surface_geom_spx,surface_geometry,geometry,1,0,0)');
INSERT INTO citydb.index_table (id, obj) VALUES (3, '(surface_geom_solid_spx,surface_geometry,solid_geometry,1,0,0)');
INSERT INTO citydb.index_table (id, obj) VALUES (4, '(cityobject_inx,cityobject,"gmlid, gmlid_codespace",0,0,0)');
INSERT INTO citydb.index_table (id, obj) VALUES (5, '(cityobject_lineage_inx,cityobject,lineage,0,0,0)');
INSERT INTO citydb.index_table (id, obj) VALUES (6, '(cityobj_creation_date_inx,cityobject,creation_date,0,0,0)');
INSERT INTO citydb.index_table (id, obj) VALUES (7, '(cityobj_term_date_inx,cityobject,termination_date,0,0,0)');
INSERT INTO citydb.index_table (id, obj) VALUES (8, '(cityobj_last_mod_date_inx,cityobject,last_modification_date,0,0,0)');
INSERT INTO citydb.index_table (id, obj) VALUES (9, '(surface_geom_inx,surface_geometry,"gmlid, gmlid_codespace",0,0,0)');
INSERT INTO citydb.index_table (id, obj) VALUES (10, '(appearance_inx,appearance,"gmlid, gmlid_codespace",0,0,0)');
INSERT INTO citydb.index_table (id, obj) VALUES (11, '(appearance_theme_inx,appearance,theme,0,0,0)');
INSERT INTO citydb.index_table (id, obj) VALUES (12, '(surface_data_inx,surface_data,"gmlid, gmlid_codespace",0,0,0)');
INSERT INTO citydb.index_table (id, obj) VALUES (13, '(address_inx,address,"gmlid, gmlid_codespace",0,0,0)');


--
-- TOC entry 6082 (class 0 OID 33239)
-- Dependencies: 272
-- Data for Name: land_use; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6083 (class 0 OID 33244)
-- Dependencies: 273
-- Data for Name: masspoint_relief; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6084 (class 0 OID 33249)
-- Dependencies: 274
-- Data for Name: objectclass; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (0, 0, 0, 'Undefined', NULL, NULL, NULL, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (1, 0, 0, '_GML', 'cityobject', NULL, NULL, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (2, 0, 0, '_Feature', 'cityobject', 1, 1, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (3, 0, 0, '_CityObject', 'cityobject', 2, 2, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (4, 0, 1, 'LandUse', 'land_use', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (5, 0, 1, 'GenericCityObject', 'generic_cityobject', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (6, 0, 0, '_VegetationObject', 'cityobject', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (7, 0, 1, 'SolitaryVegetationObject', 'solitary_vegetat_object', 6, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (8, 0, 1, 'PlantCover', 'plant_cover', 6, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (105, 0, 0, '_WaterObject', 'cityobject', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (9, 0, 1, 'WaterBody', 'waterbody', 105, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (10, 0, 0, '_WaterBoundarySurface', 'waterboundary_surface', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (11, 0, 0, 'WaterSurface', 'waterboundary_surface', 10, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (12, 0, 0, 'WaterGroundSurface', 'waterboundary_surface', 10, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (13, 0, 0, 'WaterClosureSurface', 'waterboundary_surface', 10, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (14, 0, 1, 'ReliefFeature', 'relief_feature', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (15, 0, 0, '_ReliefComponent', 'relief_component', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (16, 0, 0, 'TINRelief', 'tin_relief', 15, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (17, 0, 0, 'MassPointRelief', 'masspoint_relief', 15, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (18, 0, 0, 'BreaklineRelief', 'breakline_relief', 15, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (19, 0, 0, 'RasterRelief', 'raster_relief', 15, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (20, 0, 0, '_Site', 'cityobject', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (21, 0, 1, 'CityFurniture', 'city_furniture', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (22, 0, 0, '_TransportationObject', 'cityobject', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (23, 0, 1, 'CityObjectGroup', 'cityobjectgroup', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (24, 0, 0, '_AbstractBuilding', 'building', 20, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (25, 0, 0, 'BuildingPart', 'building', 24, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (26, 0, 1, 'Building', 'building', 24, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (27, 0, 0, 'BuildingInstallation', 'building_installation', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (28, 0, 0, 'IntBuildingInstallation', 'building_installation', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (29, 0, 0, '_BuildingBoundarySurface', 'thematic_surface', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (30, 0, 0, 'BuildingCeilingSurface', 'thematic_surface', 29, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (31, 0, 0, 'InteriorBuildingWallSurface', 'thematic_surface', 29, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (32, 0, 0, 'BuildingFloorSurface', 'thematic_surface', 29, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (33, 0, 0, 'BuildingRoofSurface', 'thematic_surface', 29, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (34, 0, 0, 'BuildingWallSurface', 'thematic_surface', 29, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (35, 0, 0, 'BuildingGroundSurface', 'thematic_surface', 29, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (36, 0, 0, 'BuildingClosureSurface', 'thematic_surface', 29, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (37, 0, 0, '_BuildingOpening', 'opening', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (38, 0, 0, 'BuildingWindow', 'opening', 37, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (39, 0, 0, 'BuildingDoor', 'opening', 37, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (40, 0, 0, 'BuildingFurniture', 'building_furniture', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (41, 0, 0, 'BuildingRoom', 'room', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (42, 0, 1, 'TransportationComplex', 'transportation_complex', 22, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (43, 0, 1, 'Track', 'transportation_complex', 42, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (44, 0, 1, 'Railway', 'transportation_complex', 42, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (45, 0, 1, 'Road', 'transportation_complex', 42, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (46, 0, 1, 'Square', 'transportation_complex', 42, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (47, 0, 0, 'TrafficArea', 'traffic_area', 22, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (48, 0, 0, 'AuxiliaryTrafficArea', 'traffic_area', 22, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (49, 0, 0, 'FeatureCollection', 'cityobject', 2, 2, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (50, 0, 0, 'Appearance', 'appearance', 2, 2, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (51, 0, 0, '_SurfaceData', 'surface_data', 2, 2, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (52, 0, 0, '_Texture', 'surface_data', 51, 2, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (53, 0, 0, 'X3DMaterial', 'surface_data', 51, 2, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (54, 0, 0, 'ParameterizedTexture', 'surface_data', 52, 2, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (55, 0, 0, 'GeoreferencedTexture', 'surface_data', 52, 2, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (56, 0, 0, '_TextureParametrization', 'textureparam', 1, 1, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (57, 0, 0, 'CityModel', 'citymodel', 49, 2, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (58, 0, 0, 'Address', 'address', 2, 2, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (59, 0, 0, 'ImplicitGeometry', 'implicit_geometry', 1, 1, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (60, 0, 0, 'OuterBuildingCeilingSurface', 'thematic_surface', 29, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (61, 0, 0, 'OuterBuildingFloorSurface', 'thematic_surface', 29, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (62, 0, 0, '_AbstractBridge', 'bridge', 20, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (63, 0, 0, 'BridgePart', 'bridge', 62, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (64, 0, 1, 'Bridge', 'bridge', 62, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (65, 0, 0, 'BridgeInstallation', 'bridge_installation', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (66, 0, 0, 'IntBridgeInstallation', 'bridge_installation', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (67, 0, 0, '_BridgeBoundarySurface', 'bridge_thematic_surface', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (68, 0, 0, 'BridgeCeilingSurface', 'bridge_thematic_surface', 67, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (69, 0, 0, 'InteriorBridgeWallSurface', 'bridge_thematic_surface', 67, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (70, 0, 0, 'BridgeFloorSurface', 'bridge_thematic_surface', 67, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (71, 0, 0, 'BridgeRoofSurface', 'bridge_thematic_surface', 67, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (72, 0, 0, 'BridgeWallSurface', 'bridge_thematic_surface', 67, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (73, 0, 0, 'BridgeGroundSurface', 'bridge_thematic_surface', 67, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (74, 0, 0, 'BridgeClosureSurface', 'bridge_thematic_surface', 67, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (75, 0, 0, 'OuterBridgeCeilingSurface', 'bridge_thematic_surface', 67, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (76, 0, 0, 'OuterBridgeFloorSurface', 'bridge_thematic_surface', 67, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (77, 0, 0, '_BridgeOpening', 'bridge_opening', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (78, 0, 0, 'BridgeWindow', 'bridge_opening', 77, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (79, 0, 0, 'BridgeDoor', 'bridge_opening', 77, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (80, 0, 0, 'BridgeFurniture', 'bridge_furniture', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (81, 0, 0, 'BridgeRoom', 'bridge_room', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (82, 0, 0, 'BridgeConstructionElement', 'bridge_constr_element', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (83, 0, 0, '_AbstractTunnel', 'tunnel', 20, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (84, 0, 0, 'TunnelPart', 'tunnel', 83, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (85, 0, 1, 'Tunnel', 'tunnel', 83, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (86, 0, 0, 'TunnelInstallation', 'tunnel_installation', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (87, 0, 0, 'IntTunnelInstallation', 'tunnel_installation', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (88, 0, 0, '_TunnelBoundarySurface', 'tunnel_thematic_surface', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (89, 0, 0, 'TunnelCeilingSurface', 'tunnel_thematic_surface', 88, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (90, 0, 0, 'InteriorTunnelWallSurface', 'tunnel_thematic_surface', 88, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (91, 0, 0, 'TunnelFloorSurface', 'tunnel_thematic_surface', 88, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (92, 0, 0, 'TunnelRoofSurface', 'tunnel_thematic_surface', 88, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (93, 0, 0, 'TunnelWallSurface', 'tunnel_thematic_surface', 88, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (94, 0, 0, 'TunnelGroundSurface', 'tunnel_thematic_surface', 88, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (95, 0, 0, 'TunnelClosureSurface', 'tunnel_thematic_surface', 88, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (96, 0, 0, 'OuterTunnelCeilingSurface', 'tunnel_thematic_surface', 88, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (97, 0, 0, 'OuterTunnelFloorSurface', 'tunnel_thematic_surface', 88, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (98, 0, 0, '_TunnelOpening', 'tunnel_opening', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (99, 0, 0, 'TunnelWindow', 'tunnel_opening', 98, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (100, 0, 0, 'TunnelDoor', 'tunnel_opening', 98, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (101, 0, 0, 'TunnelFurniture', 'tunnel_furniture', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (102, 0, 0, 'HollowSpace', 'tunnel_hollow_space', 3, 3, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (103, 0, 0, 'TexCoordList', 'textureparam', 56, 1, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (104, 0, 0, 'TexCoordGen', 'textureparam', 56, 1, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (106, 0, 0, '_BrepGeometry', 'surface_geometry', 0, 1, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (107, 0, 0, 'Polygon', 'surface_geometry', 106, 1, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (108, 0, 0, 'BrepAggregate', 'surface_geometry', 106, 1, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (109, 0, 0, 'TexImage', 'tex_image', 0, 0, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (110, 0, 0, 'ExternalReference', 'external_reference', 0, 0, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (111, 0, 0, 'GridCoverage', 'grid_coverage', 0, 0, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (112, 0, 0, '_genericAttribute', 'cityobject_genericattrib', 0, 0, NULL);
INSERT INTO citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) VALUES (113, 0, 0, 'genericAttributeSet', 'cityobject_genericattrib', 112, 0, NULL);


--
-- TOC entry 6085 (class 0 OID 33254)
-- Dependencies: 275
-- Data for Name: opening; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6086 (class 0 OID 33259)
-- Dependencies: 276
-- Data for Name: opening_to_them_surface; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6087 (class 0 OID 33262)
-- Dependencies: 277
-- Data for Name: plant_cover; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6088 (class 0 OID 33267)
-- Dependencies: 278
-- Data for Name: raster_relief; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6089 (class 0 OID 33272)
-- Dependencies: 279
-- Data for Name: relief_component; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6090 (class 0 OID 33278)
-- Dependencies: 280
-- Data for Name: relief_feat_to_rel_comp; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6091 (class 0 OID 33281)
-- Dependencies: 281
-- Data for Name: relief_feature; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6092 (class 0 OID 33287)
-- Dependencies: 282
-- Data for Name: room; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6094 (class 0 OID 33293)
-- Dependencies: 284
-- Data for Name: schema; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6095 (class 0 OID 33299)
-- Dependencies: 285
-- Data for Name: schema_referencing; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6096 (class 0 OID 33302)
-- Dependencies: 286
-- Data for Name: schema_to_objectclass; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6097 (class 0 OID 33305)
-- Dependencies: 287
-- Data for Name: solitary_vegetat_object; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6099 (class 0 OID 33317)
-- Dependencies: 289
-- Data for Name: surface_data; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6101 (class 0 OID 33324)
-- Dependencies: 291
-- Data for Name: surface_geometry; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

INSERT INTO citydb.surface_geometry (id, gmlid, gmlid_codespace, parent_id, root_id, is_solid, is_composite, is_triangulated, is_xlink, is_reverse, solid_geometry, geometry, implicit_geometry, cityobject_id) VALUES (1, 'ID_cb37679d-e0c0-4a3d-8473-3af35c536bff', NULL, NULL, 1, 0, 0, 0, 0, 0, NULL, NULL, NULL, 2);
INSERT INTO citydb.surface_geometry (id, gmlid, gmlid_codespace, parent_id, root_id, is_solid, is_composite, is_triangulated, is_xlink, is_reverse, solid_geometry, geometry, implicit_geometry, cityobject_id) VALUES (2, 'UUID_f724cdb3-97b8-4765-bb6a-d835b69a49f6', NULL, 1, 1, 0, 0, 0, 0, 0, NULL, '01030000A06A0F000001000000040000003A77BB167D1E3C41CEC474364BBE5341516B9A779CFC674098141FC77B1E3C41D0436D374BBE534127A089B0E10D6840973787C37A1E3C415B5F24FD4ABE53418AADA069891B68403A77BB167D1E3C41CEC474364BBE5341516B9A779CFC6740', NULL, 2);
INSERT INTO citydb.surface_geometry (id, gmlid, gmlid_codespace, parent_id, root_id, is_solid, is_composite, is_triangulated, is_xlink, is_reverse, solid_geometry, geometry, implicit_geometry, cityobject_id) VALUES (4, 'ID_d62119e2-3f8f-49d1-8518-cb303ff5699c', NULL, NULL, 4, 0, 0, 0, 0, 0, NULL, NULL, NULL, 3);
INSERT INTO citydb.surface_geometry (id, gmlid, gmlid_codespace, parent_id, root_id, is_solid, is_composite, is_triangulated, is_xlink, is_reverse, solid_geometry, geometry, implicit_geometry, cityobject_id) VALUES (5, 'UUID_72378318-3ae3-4434-b2c2-6b97240a4ff2', NULL, 4, 4, 0, 0, 0, 0, 0, NULL, '01030000A06A0F000001000000050000005B7A34C57A1E3C410EDAAB4B4BBE5341DBF97E6ABC166840973787C37A1E3C415B5F24FD4ABE5341DBF97E6ABC166840973787C37A1E3C415B5F24FD4ABE53418AADA069891B68405B7A34C57A1E3C410EDAAB4B4BBE53418AADA069891B68405B7A34C57A1E3C410EDAAB4B4BBE5341DBF97E6ABC166840', NULL, 3);


--
-- TOC entry 6103 (class 0 OID 33331)
-- Dependencies: 293
-- Data for Name: tex_image; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6104 (class 0 OID 33337)
-- Dependencies: 294
-- Data for Name: textureparam; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6105 (class 0 OID 33342)
-- Dependencies: 295
-- Data for Name: thematic_surface; Type: TABLE DATA; Schema: citydb; Owner: postgres
--

INSERT INTO citydb.thematic_surface (id, objectclass_id, building_id, room_id, building_installation_id, lod2_multi_surface_id, lod3_multi_surface_id, lod4_multi_surface_id) VALUES (2, 33, 1, NULL, NULL, 1, NULL, NULL);
INSERT INTO citydb.thematic_surface (id, objectclass_id, building_id, room_id, building_installation_id, lod2_multi_surface_id, lod3_multi_surface_id, lod4_multi_surface_id) VALUES (3, 34, 1, NULL, NULL, 4, NULL, NULL);


--
-- TOC entry 6106 (class 0 OID 33345)
-- Dependencies: 296
-- Data for Name: tin_relief; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6107 (class 0 OID 33350)
-- Dependencies: 297
-- Data for Name: traffic_area; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6108 (class 0 OID 33355)
-- Dependencies: 298
-- Data for Name: transportation_complex; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6109 (class 0 OID 33360)
-- Dependencies: 299
-- Data for Name: tunnel; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6110 (class 0 OID 33365)
-- Dependencies: 300
-- Data for Name: tunnel_furniture; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6111 (class 0 OID 33370)
-- Dependencies: 301
-- Data for Name: tunnel_hollow_space; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6112 (class 0 OID 33375)
-- Dependencies: 302
-- Data for Name: tunnel_installation; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6113 (class 0 OID 33380)
-- Dependencies: 303
-- Data for Name: tunnel_open_to_them_srf; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6114 (class 0 OID 33383)
-- Dependencies: 304
-- Data for Name: tunnel_opening; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6115 (class 0 OID 33388)
-- Dependencies: 305
-- Data for Name: tunnel_thematic_surface; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6116 (class 0 OID 33391)
-- Dependencies: 306
-- Data for Name: waterbod_to_waterbnd_srf; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6117 (class 0 OID 33394)
-- Dependencies: 307
-- Data for Name: waterbody; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 6118 (class 0 OID 33399)
-- Dependencies: 308
-- Data for Name: waterboundary_surface; Type: TABLE DATA; Schema: citydb; Owner: postgres
--



--
-- TOC entry 5064 (class 0 OID 31604)
-- Dependencies: 214
-- Data for Name: spatial_ref_sys; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- TOC entry 6125 (class 0 OID 0)
-- Dependencies: 229
-- Name: address_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.address_seq', 1, false);


--
-- TOC entry 6126 (class 0 OID 0)
-- Dependencies: 233
-- Name: ade_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.ade_seq', 1, false);


--
-- TOC entry 6127 (class 0 OID 0)
-- Dependencies: 237
-- Name: appearance_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.appearance_seq', 1, false);


--
-- TOC entry 6128 (class 0 OID 0)
-- Dependencies: 252
-- Name: citymodel_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.citymodel_seq', 1, false);


--
-- TOC entry 6129 (class 0 OID 0)
-- Dependencies: 256
-- Name: cityobject_genericatt_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.cityobject_genericatt_seq', 1, false);


--
-- TOC entry 6130 (class 0 OID 0)
-- Dependencies: 254
-- Name: cityobject_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.cityobject_seq', 3, true);


--
-- TOC entry 6131 (class 0 OID 0)
-- Dependencies: 261
-- Name: external_ref_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.external_ref_seq', 1, false);


--
-- TOC entry 6132 (class 0 OID 0)
-- Dependencies: 265
-- Name: grid_coverage_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.grid_coverage_seq', 1, false);


--
-- TOC entry 6133 (class 0 OID 0)
-- Dependencies: 268
-- Name: implicit_geometry_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.implicit_geometry_seq', 1, false);


--
-- TOC entry 6134 (class 0 OID 0)
-- Dependencies: 271
-- Name: index_table_id_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.index_table_id_seq', 13, true);


--
-- TOC entry 6135 (class 0 OID 0)
-- Dependencies: 283
-- Name: schema_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.schema_seq', 1, false);


--
-- TOC entry 6136 (class 0 OID 0)
-- Dependencies: 288
-- Name: surface_data_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.surface_data_seq', 1, false);


--
-- TOC entry 6137 (class 0 OID 0)
-- Dependencies: 290
-- Name: surface_geometry_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.surface_geometry_seq', 6, true);


--
-- TOC entry 6138 (class 0 OID 0)
-- Dependencies: 292
-- Name: tex_image_seq; Type: SEQUENCE SET; Schema: citydb; Owner: postgres
--

SELECT pg_catalog.setval('citydb.tex_image_seq', 1, false);


--
-- TOC entry 5086 (class 2606 OID 33407)
-- Name: address address_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.address
    ADD CONSTRAINT address_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5091 (class 2606 OID 33409)
-- Name: address_to_bridge address_to_bridge_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.address_to_bridge
    ADD CONSTRAINT address_to_bridge_pk PRIMARY KEY (bridge_id, address_id) WITH (fillfactor='100');


--
-- TOC entry 5095 (class 2606 OID 33411)
-- Name: address_to_building address_to_building_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.address_to_building
    ADD CONSTRAINT address_to_building_pk PRIMARY KEY (building_id, address_id) WITH (fillfactor='100');


--
-- TOC entry 5097 (class 2606 OID 33413)
-- Name: ade ade_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.ade
    ADD CONSTRAINT ade_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5099 (class 2606 OID 33415)
-- Name: aggregation_info aggregation_info_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.aggregation_info
    ADD CONSTRAINT aggregation_info_pk PRIMARY KEY (child_id, parent_id, join_table_or_column_name);


--
-- TOC entry 5103 (class 2606 OID 33417)
-- Name: appear_to_surface_data appear_to_surface_data_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.appear_to_surface_data
    ADD CONSTRAINT appear_to_surface_data_pk PRIMARY KEY (surface_data_id, appearance_id) WITH (fillfactor='100');


--
-- TOC entry 5108 (class 2606 OID 33419)
-- Name: appearance appearance_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.appearance
    ADD CONSTRAINT appearance_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5113 (class 2606 OID 33421)
-- Name: breakline_relief breakline_relief_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.breakline_relief
    ADD CONSTRAINT breakline_relief_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5145 (class 2606 OID 33423)
-- Name: bridge_constr_element bridge_constr_element_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_element_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5166 (class 2606 OID 33425)
-- Name: bridge_furniture bridge_furniture_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_furniture
    ADD CONSTRAINT bridge_furniture_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5183 (class 2606 OID 33427)
-- Name: bridge_installation bridge_installation_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_installation_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5187 (class 2606 OID 33429)
-- Name: bridge_open_to_them_srf bridge_open_to_them_srf_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_open_to_them_srf
    ADD CONSTRAINT bridge_open_to_them_srf_pk PRIMARY KEY (bridge_opening_id, bridge_thematic_surface_id) WITH (fillfactor='100');


--
-- TOC entry 5197 (class 2606 OID 33431)
-- Name: bridge_opening bridge_opening_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_opening_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5133 (class 2606 OID 33433)
-- Name: bridge bridge_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5203 (class 2606 OID 33435)
-- Name: bridge_room bridge_room_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_room
    ADD CONSTRAINT bridge_room_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5213 (class 2606 OID 33437)
-- Name: bridge_thematic_surface bridge_thematic_surface_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT bridge_thematic_surface_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5243 (class 2606 OID 33439)
-- Name: building_furniture building_furniture_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_furniture
    ADD CONSTRAINT building_furniture_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5260 (class 2606 OID 33441)
-- Name: building_installation building_installation_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT building_installation_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5234 (class 2606 OID 33443)
-- Name: building building_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5283 (class 2606 OID 33445)
-- Name: city_furniture city_furniture_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furniture_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5287 (class 2606 OID 33447)
-- Name: citymodel citymodel_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.citymodel
    ADD CONSTRAINT citymodel_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5298 (class 2606 OID 33449)
-- Name: cityobject_genericattrib cityobj_genericattrib_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobject_genericattrib
    ADD CONSTRAINT cityobj_genericattrib_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5306 (class 2606 OID 33451)
-- Name: cityobject_member cityobject_member_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobject_member
    ADD CONSTRAINT cityobject_member_pk PRIMARY KEY (citymodel_id, cityobject_id) WITH (fillfactor='100');


--
-- TOC entry 5296 (class 2606 OID 33453)
-- Name: cityobject cityobject_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobject
    ADD CONSTRAINT cityobject_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5308 (class 2606 OID 33455)
-- Name: cityobjectgroup cityobjectgroup_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobjectgroup
    ADD CONSTRAINT cityobjectgroup_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5314 (class 2606 OID 33457)
-- Name: database_srs database_srs_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.database_srs
    ADD CONSTRAINT database_srs_pk PRIMARY KEY (srid) WITH (fillfactor='100');


--
-- TOC entry 5317 (class 2606 OID 33459)
-- Name: external_reference external_reference_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.external_reference
    ADD CONSTRAINT external_reference_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5321 (class 2606 OID 33461)
-- Name: generalization generalization_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generalization
    ADD CONSTRAINT generalization_pk PRIMARY KEY (cityobject_id, generalizes_to_id) WITH (fillfactor='100');


--
-- TOC entry 5349 (class 2606 OID 33463)
-- Name: generic_cityobject generic_cityobject_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT generic_cityobject_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5351 (class 2606 OID 33465)
-- Name: grid_coverage grid_coverage_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.grid_coverage
    ADD CONSTRAINT grid_coverage_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5356 (class 2606 OID 33467)
-- Name: group_to_cityobject group_to_cityobject_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.group_to_cityobject
    ADD CONSTRAINT group_to_cityobject_pk PRIMARY KEY (cityobject_id, cityobjectgroup_id) WITH (fillfactor='100');


--
-- TOC entry 5360 (class 2606 OID 33469)
-- Name: implicit_geometry implicit_geometry_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.implicit_geometry
    ADD CONSTRAINT implicit_geometry_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5362 (class 2606 OID 33471)
-- Name: index_table index_table_pkey; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.index_table
    ADD CONSTRAINT index_table_pkey PRIMARY KEY (id);


--
-- TOC entry 5370 (class 2606 OID 33473)
-- Name: land_use land_use_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5373 (class 2606 OID 33475)
-- Name: masspoint_relief masspoint_relief_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.masspoint_relief
    ADD CONSTRAINT masspoint_relief_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5377 (class 2606 OID 33477)
-- Name: objectclass objectclass_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.objectclass
    ADD CONSTRAINT objectclass_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5388 (class 2606 OID 33479)
-- Name: opening opening_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5392 (class 2606 OID 33481)
-- Name: opening_to_them_surface opening_to_them_surface_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.opening_to_them_surface
    ADD CONSTRAINT opening_to_them_surface_pk PRIMARY KEY (opening_id, thematic_surface_id) WITH (fillfactor='100');


--
-- TOC entry 5403 (class 2606 OID 33483)
-- Name: plant_cover plant_cover_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5407 (class 2606 OID 33485)
-- Name: raster_relief raster_relief_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.raster_relief
    ADD CONSTRAINT raster_relief_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5411 (class 2606 OID 33487)
-- Name: relief_component relief_component_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.relief_component
    ADD CONSTRAINT relief_component_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5415 (class 2606 OID 33489)
-- Name: relief_feat_to_rel_comp relief_feat_to_rel_comp_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.relief_feat_to_rel_comp
    ADD CONSTRAINT relief_feat_to_rel_comp_pk PRIMARY KEY (relief_component_id, relief_feature_id) WITH (fillfactor='100');


--
-- TOC entry 5418 (class 2606 OID 33491)
-- Name: relief_feature relief_feature_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.relief_feature
    ADD CONSTRAINT relief_feature_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5424 (class 2606 OID 33493)
-- Name: room room_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.room
    ADD CONSTRAINT room_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5426 (class 2606 OID 33495)
-- Name: schema schema_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.schema
    ADD CONSTRAINT schema_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5430 (class 2606 OID 33497)
-- Name: schema_referencing schema_referencing_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.schema_referencing
    ADD CONSTRAINT schema_referencing_pk PRIMARY KEY (referenced_id, referencing_id) WITH (fillfactor='100');


--
-- TOC entry 5434 (class 2606 OID 33499)
-- Name: schema_to_objectclass schema_to_objectclass_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.schema_to_objectclass
    ADD CONSTRAINT schema_to_objectclass_pk PRIMARY KEY (schema_id, objectclass_id) WITH (fillfactor='100');


--
-- TOC entry 5453 (class 2606 OID 33501)
-- Name: solitary_vegetat_object solitary_veg_object_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT solitary_veg_object_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5457 (class 2606 OID 33503)
-- Name: surface_data surface_data_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.surface_data
    ADD CONSTRAINT surface_data_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5467 (class 2606 OID 33505)
-- Name: surface_geometry surface_geometry_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.surface_geometry
    ADD CONSTRAINT surface_geometry_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5469 (class 2606 OID 33507)
-- Name: tex_image tex_image_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tex_image
    ADD CONSTRAINT tex_image_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5473 (class 2606 OID 33509)
-- Name: textureparam textureparam_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.textureparam
    ADD CONSTRAINT textureparam_pk PRIMARY KEY (surface_geometry_id, surface_data_id) WITH (fillfactor='100');


--
-- TOC entry 5482 (class 2606 OID 33511)
-- Name: thematic_surface thematic_surface_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT thematic_surface_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5488 (class 2606 OID 33513)
-- Name: tin_relief tin_relief_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tin_relief
    ADD CONSTRAINT tin_relief_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5495 (class 2606 OID 33515)
-- Name: traffic_area traffic_area_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.traffic_area
    ADD CONSTRAINT traffic_area_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5504 (class 2606 OID 33517)
-- Name: transportation_complex transportation_complex_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.transportation_complex
    ADD CONSTRAINT transportation_complex_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5532 (class 2606 OID 33519)
-- Name: tunnel_furniture tunnel_furniture_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_furniture
    ADD CONSTRAINT tunnel_furniture_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5538 (class 2606 OID 33521)
-- Name: tunnel_hollow_space tunnel_hollow_space_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_hollow_space
    ADD CONSTRAINT tunnel_hollow_space_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5555 (class 2606 OID 33523)
-- Name: tunnel_installation tunnel_installation_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_installation_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5559 (class 2606 OID 33525)
-- Name: tunnel_open_to_them_srf tunnel_open_to_them_srf_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_open_to_them_srf
    ADD CONSTRAINT tunnel_open_to_them_srf_pk PRIMARY KEY (tunnel_opening_id, tunnel_thematic_surface_id) WITH (fillfactor='100');


--
-- TOC entry 5568 (class 2606 OID 33527)
-- Name: tunnel_opening tunnel_opening_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_opening
    ADD CONSTRAINT tunnel_opening_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5523 (class 2606 OID 33529)
-- Name: tunnel tunnel_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5577 (class 2606 OID 33531)
-- Name: tunnel_thematic_surface tunnel_thematic_surface_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tunnel_thematic_surface_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5581 (class 2606 OID 33533)
-- Name: waterbod_to_waterbnd_srf waterbod_to_waterbnd_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbod_to_waterbnd_srf
    ADD CONSTRAINT waterbod_to_waterbnd_pk PRIMARY KEY (waterboundary_surface_id, waterbody_id) WITH (fillfactor='100');


--
-- TOC entry 5592 (class 2606 OID 33535)
-- Name: waterbody waterbody_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5598 (class 2606 OID 33537)
-- Name: waterboundary_surface waterboundary_surface_pk; Type: CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterboundary_surface
    ADD CONSTRAINT waterboundary_surface_pk PRIMARY KEY (id) WITH (fillfactor='100');


--
-- TOC entry 5084 (class 1259 OID 33538)
-- Name: address_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX address_inx ON citydb.address USING btree (gmlid, gmlid_codespace);


--
-- TOC entry 5087 (class 1259 OID 33539)
-- Name: address_point_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX address_point_spx ON citydb.address USING gist (multi_point);


--
-- TOC entry 5088 (class 1259 OID 33540)
-- Name: address_to_bridge_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX address_to_bridge_fkx ON citydb.address_to_bridge USING btree (address_id) WITH (fillfactor='90');


--
-- TOC entry 5089 (class 1259 OID 33541)
-- Name: address_to_bridge_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX address_to_bridge_fkx1 ON citydb.address_to_bridge USING btree (bridge_id) WITH (fillfactor='90');


--
-- TOC entry 5092 (class 1259 OID 33542)
-- Name: address_to_building_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX address_to_building_fkx ON citydb.address_to_building USING btree (address_id) WITH (fillfactor='90');


--
-- TOC entry 5093 (class 1259 OID 33543)
-- Name: address_to_building_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX address_to_building_fkx1 ON citydb.address_to_building USING btree (building_id) WITH (fillfactor='90');


--
-- TOC entry 5100 (class 1259 OID 33544)
-- Name: app_to_surf_data_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX app_to_surf_data_fkx ON citydb.appear_to_surface_data USING btree (surface_data_id) WITH (fillfactor='90');


--
-- TOC entry 5101 (class 1259 OID 33545)
-- Name: app_to_surf_data_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX app_to_surf_data_fkx1 ON citydb.appear_to_surface_data USING btree (appearance_id) WITH (fillfactor='90');


--
-- TOC entry 5104 (class 1259 OID 33546)
-- Name: appearance_citymodel_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX appearance_citymodel_fkx ON citydb.appearance USING btree (citymodel_id) WITH (fillfactor='90');


--
-- TOC entry 5105 (class 1259 OID 33547)
-- Name: appearance_cityobject_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX appearance_cityobject_fkx ON citydb.appearance USING btree (cityobject_id) WITH (fillfactor='90');


--
-- TOC entry 5106 (class 1259 OID 33548)
-- Name: appearance_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX appearance_inx ON citydb.appearance USING btree (gmlid, gmlid_codespace) WITH (fillfactor='90');


--
-- TOC entry 5109 (class 1259 OID 33549)
-- Name: appearance_theme_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX appearance_theme_inx ON citydb.appearance USING btree (theme) WITH (fillfactor='90');


--
-- TOC entry 5236 (class 1259 OID 33550)
-- Name: bldg_furn_lod4brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_furn_lod4brep_fkx ON citydb.building_furniture USING btree (lod4_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5237 (class 1259 OID 33551)
-- Name: bldg_furn_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_furn_lod4impl_fkx ON citydb.building_furniture USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5238 (class 1259 OID 33552)
-- Name: bldg_furn_lod4refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_furn_lod4refpt_spx ON citydb.building_furniture USING gist (lod4_implicit_ref_point);


--
-- TOC entry 5239 (class 1259 OID 33553)
-- Name: bldg_furn_lod4xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_furn_lod4xgeom_spx ON citydb.building_furniture USING gist (lod4_other_geom);


--
-- TOC entry 5240 (class 1259 OID 33554)
-- Name: bldg_furn_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_furn_objclass_fkx ON citydb.building_furniture USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5241 (class 1259 OID 33555)
-- Name: bldg_furn_room_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_furn_room_fkx ON citydb.building_furniture USING btree (room_id) WITH (fillfactor='90');


--
-- TOC entry 5244 (class 1259 OID 33556)
-- Name: bldg_inst_building_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_building_fkx ON citydb.building_installation USING btree (building_id) WITH (fillfactor='90');


--
-- TOC entry 5245 (class 1259 OID 33557)
-- Name: bldg_inst_lod2brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod2brep_fkx ON citydb.building_installation USING btree (lod2_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5246 (class 1259 OID 33558)
-- Name: bldg_inst_lod2impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod2impl_fkx ON citydb.building_installation USING btree (lod2_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5247 (class 1259 OID 33559)
-- Name: bldg_inst_lod2refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod2refpt_spx ON citydb.building_installation USING gist (lod2_implicit_ref_point);


--
-- TOC entry 5248 (class 1259 OID 33560)
-- Name: bldg_inst_lod2xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod2xgeom_spx ON citydb.building_installation USING gist (lod2_other_geom);


--
-- TOC entry 5249 (class 1259 OID 33561)
-- Name: bldg_inst_lod3brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod3brep_fkx ON citydb.building_installation USING btree (lod3_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5250 (class 1259 OID 33562)
-- Name: bldg_inst_lod3impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod3impl_fkx ON citydb.building_installation USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5251 (class 1259 OID 33563)
-- Name: bldg_inst_lod3refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod3refpt_spx ON citydb.building_installation USING gist (lod3_implicit_ref_point);


--
-- TOC entry 5252 (class 1259 OID 33564)
-- Name: bldg_inst_lod3xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod3xgeom_spx ON citydb.building_installation USING gist (lod3_other_geom);


--
-- TOC entry 5253 (class 1259 OID 33565)
-- Name: bldg_inst_lod4brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod4brep_fkx ON citydb.building_installation USING btree (lod4_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5254 (class 1259 OID 33566)
-- Name: bldg_inst_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod4impl_fkx ON citydb.building_installation USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5255 (class 1259 OID 33567)
-- Name: bldg_inst_lod4refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod4refpt_spx ON citydb.building_installation USING gist (lod4_implicit_ref_point);


--
-- TOC entry 5256 (class 1259 OID 33568)
-- Name: bldg_inst_lod4xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_lod4xgeom_spx ON citydb.building_installation USING gist (lod4_other_geom);


--
-- TOC entry 5257 (class 1259 OID 33569)
-- Name: bldg_inst_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_objclass_fkx ON citydb.building_installation USING btree (objectclass_id);


--
-- TOC entry 5258 (class 1259 OID 33570)
-- Name: bldg_inst_room_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bldg_inst_room_fkx ON citydb.building_installation USING btree (room_id) WITH (fillfactor='90');


--
-- TOC entry 5184 (class 1259 OID 33571)
-- Name: brd_open_to_them_srf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX brd_open_to_them_srf_fkx ON citydb.bridge_open_to_them_srf USING btree (bridge_opening_id) WITH (fillfactor='90');


--
-- TOC entry 5185 (class 1259 OID 33572)
-- Name: brd_open_to_them_srf_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX brd_open_to_them_srf_fkx1 ON citydb.bridge_open_to_them_srf USING btree (bridge_thematic_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5204 (class 1259 OID 33573)
-- Name: brd_them_srf_brd_const_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX brd_them_srf_brd_const_fkx ON citydb.bridge_thematic_surface USING btree (bridge_constr_element_id) WITH (fillfactor='90');


--
-- TOC entry 5205 (class 1259 OID 33574)
-- Name: brd_them_srf_brd_inst_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX brd_them_srf_brd_inst_fkx ON citydb.bridge_thematic_surface USING btree (bridge_installation_id) WITH (fillfactor='90');


--
-- TOC entry 5206 (class 1259 OID 33575)
-- Name: brd_them_srf_brd_room_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX brd_them_srf_brd_room_fkx ON citydb.bridge_thematic_surface USING btree (bridge_room_id) WITH (fillfactor='90');


--
-- TOC entry 5207 (class 1259 OID 33576)
-- Name: brd_them_srf_bridge_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX brd_them_srf_bridge_fkx ON citydb.bridge_thematic_surface USING btree (bridge_id) WITH (fillfactor='90');


--
-- TOC entry 5208 (class 1259 OID 33577)
-- Name: brd_them_srf_lod2msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX brd_them_srf_lod2msrf_fkx ON citydb.bridge_thematic_surface USING btree (lod2_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5209 (class 1259 OID 33578)
-- Name: brd_them_srf_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX brd_them_srf_lod3msrf_fkx ON citydb.bridge_thematic_surface USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5210 (class 1259 OID 33579)
-- Name: brd_them_srf_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX brd_them_srf_lod4msrf_fkx ON citydb.bridge_thematic_surface USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5211 (class 1259 OID 33580)
-- Name: brd_them_srf_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX brd_them_srf_objclass_fkx ON citydb.bridge_thematic_surface USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5110 (class 1259 OID 33581)
-- Name: breakline_break_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX breakline_break_spx ON citydb.breakline_relief USING gist (break_lines);


--
-- TOC entry 5111 (class 1259 OID 33582)
-- Name: breakline_rel_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX breakline_rel_objclass_fkx ON citydb.breakline_relief USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5114 (class 1259 OID 33583)
-- Name: breakline_ridge_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX breakline_ridge_spx ON citydb.breakline_relief USING gist (ridge_or_valley_lines);


--
-- TOC entry 5135 (class 1259 OID 33584)
-- Name: bridge_const_lod1refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_const_lod1refpt_spx ON citydb.bridge_constr_element USING gist (lod1_implicit_ref_point);


--
-- TOC entry 5136 (class 1259 OID 33585)
-- Name: bridge_const_lod1xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_const_lod1xgeom_spx ON citydb.bridge_constr_element USING gist (lod1_other_geom);


--
-- TOC entry 5137 (class 1259 OID 33586)
-- Name: bridge_const_lod2refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_const_lod2refpt_spx ON citydb.bridge_constr_element USING gist (lod2_implicit_ref_point);


--
-- TOC entry 5138 (class 1259 OID 33587)
-- Name: bridge_const_lod2xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_const_lod2xgeom_spx ON citydb.bridge_constr_element USING gist (lod2_other_geom);


--
-- TOC entry 5139 (class 1259 OID 33588)
-- Name: bridge_const_lod3refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_const_lod3refpt_spx ON citydb.bridge_constr_element USING gist (lod3_implicit_ref_point);


--
-- TOC entry 5140 (class 1259 OID 33589)
-- Name: bridge_const_lod3xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_const_lod3xgeom_spx ON citydb.bridge_constr_element USING gist (lod3_other_geom);


--
-- TOC entry 5141 (class 1259 OID 33590)
-- Name: bridge_const_lod4refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_const_lod4refpt_spx ON citydb.bridge_constr_element USING gist (lod4_implicit_ref_point);


--
-- TOC entry 5142 (class 1259 OID 33591)
-- Name: bridge_const_lod4xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_const_lod4xgeom_spx ON citydb.bridge_constr_element USING gist (lod4_other_geom);


--
-- TOC entry 5143 (class 1259 OID 33592)
-- Name: bridge_constr_bridge_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_bridge_fkx ON citydb.bridge_constr_element USING btree (bridge_id) WITH (fillfactor='90');


--
-- TOC entry 5146 (class 1259 OID 33593)
-- Name: bridge_constr_lod1brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod1brep_fkx ON citydb.bridge_constr_element USING btree (lod1_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5147 (class 1259 OID 33594)
-- Name: bridge_constr_lod1impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod1impl_fkx ON citydb.bridge_constr_element USING btree (lod1_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5148 (class 1259 OID 33595)
-- Name: bridge_constr_lod1terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod1terr_spx ON citydb.bridge_constr_element USING gist (lod1_terrain_intersection);


--
-- TOC entry 5149 (class 1259 OID 33596)
-- Name: bridge_constr_lod2brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod2brep_fkx ON citydb.bridge_constr_element USING btree (lod2_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5150 (class 1259 OID 33597)
-- Name: bridge_constr_lod2impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod2impl_fkx ON citydb.bridge_constr_element USING btree (lod2_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5151 (class 1259 OID 33598)
-- Name: bridge_constr_lod2terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod2terr_spx ON citydb.bridge_constr_element USING gist (lod2_terrain_intersection);


--
-- TOC entry 5152 (class 1259 OID 33599)
-- Name: bridge_constr_lod3brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod3brep_fkx ON citydb.bridge_constr_element USING btree (lod3_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5153 (class 1259 OID 33600)
-- Name: bridge_constr_lod3impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod3impl_fkx ON citydb.bridge_constr_element USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5154 (class 1259 OID 33601)
-- Name: bridge_constr_lod3terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod3terr_spx ON citydb.bridge_constr_element USING gist (lod3_terrain_intersection);


--
-- TOC entry 5155 (class 1259 OID 33602)
-- Name: bridge_constr_lod4brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod4brep_fkx ON citydb.bridge_constr_element USING btree (lod4_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5156 (class 1259 OID 33603)
-- Name: bridge_constr_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod4impl_fkx ON citydb.bridge_constr_element USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5157 (class 1259 OID 33604)
-- Name: bridge_constr_lod4terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_lod4terr_spx ON citydb.bridge_constr_element USING gist (lod4_terrain_intersection);


--
-- TOC entry 5158 (class 1259 OID 33605)
-- Name: bridge_constr_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_constr_objclass_fkx ON citydb.bridge_constr_element USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5159 (class 1259 OID 33606)
-- Name: bridge_furn_brd_room_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_furn_brd_room_fkx ON citydb.bridge_furniture USING btree (bridge_room_id) WITH (fillfactor='90');


--
-- TOC entry 5160 (class 1259 OID 33607)
-- Name: bridge_furn_lod4brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_furn_lod4brep_fkx ON citydb.bridge_furniture USING btree (lod4_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5161 (class 1259 OID 33608)
-- Name: bridge_furn_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_furn_lod4impl_fkx ON citydb.bridge_furniture USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5162 (class 1259 OID 33609)
-- Name: bridge_furn_lod4refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_furn_lod4refpt_spx ON citydb.bridge_furniture USING gist (lod4_implicit_ref_point);


--
-- TOC entry 5163 (class 1259 OID 33610)
-- Name: bridge_furn_lod4xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_furn_lod4xgeom_spx ON citydb.bridge_furniture USING gist (lod4_other_geom);


--
-- TOC entry 5164 (class 1259 OID 33611)
-- Name: bridge_furn_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_furn_objclass_fkx ON citydb.bridge_furniture USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5167 (class 1259 OID 33612)
-- Name: bridge_inst_brd_room_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_brd_room_fkx ON citydb.bridge_installation USING btree (bridge_room_id) WITH (fillfactor='90');


--
-- TOC entry 5168 (class 1259 OID 33613)
-- Name: bridge_inst_bridge_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_bridge_fkx ON citydb.bridge_installation USING btree (bridge_id) WITH (fillfactor='90');


--
-- TOC entry 5169 (class 1259 OID 33614)
-- Name: bridge_inst_lod2brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod2brep_fkx ON citydb.bridge_installation USING btree (lod2_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5170 (class 1259 OID 33615)
-- Name: bridge_inst_lod2impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod2impl_fkx ON citydb.bridge_installation USING btree (lod2_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5171 (class 1259 OID 33616)
-- Name: bridge_inst_lod2refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod2refpt_spx ON citydb.bridge_installation USING gist (lod2_implicit_ref_point);


--
-- TOC entry 5172 (class 1259 OID 33617)
-- Name: bridge_inst_lod2xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod2xgeom_spx ON citydb.bridge_installation USING gist (lod2_other_geom);


--
-- TOC entry 5173 (class 1259 OID 33618)
-- Name: bridge_inst_lod3brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod3brep_fkx ON citydb.bridge_installation USING btree (lod3_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5174 (class 1259 OID 33619)
-- Name: bridge_inst_lod3impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod3impl_fkx ON citydb.bridge_installation USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5175 (class 1259 OID 33620)
-- Name: bridge_inst_lod3refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod3refpt_spx ON citydb.bridge_installation USING gist (lod3_implicit_ref_point);


--
-- TOC entry 5176 (class 1259 OID 33621)
-- Name: bridge_inst_lod3xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod3xgeom_spx ON citydb.bridge_installation USING gist (lod3_other_geom);


--
-- TOC entry 5177 (class 1259 OID 33622)
-- Name: bridge_inst_lod4brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod4brep_fkx ON citydb.bridge_installation USING btree (lod4_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5178 (class 1259 OID 33623)
-- Name: bridge_inst_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod4impl_fkx ON citydb.bridge_installation USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5179 (class 1259 OID 33624)
-- Name: bridge_inst_lod4refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod4refpt_spx ON citydb.bridge_installation USING gist (lod4_implicit_ref_point);


--
-- TOC entry 5180 (class 1259 OID 33625)
-- Name: bridge_inst_lod4xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_lod4xgeom_spx ON citydb.bridge_installation USING gist (lod4_other_geom);


--
-- TOC entry 5181 (class 1259 OID 33626)
-- Name: bridge_inst_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_inst_objclass_fkx ON citydb.bridge_installation USING btree (objectclass_id);


--
-- TOC entry 5115 (class 1259 OID 33627)
-- Name: bridge_lod1msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod1msrf_fkx ON citydb.bridge USING btree (lod1_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5116 (class 1259 OID 33628)
-- Name: bridge_lod1solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod1solid_fkx ON citydb.bridge USING btree (lod1_solid_id) WITH (fillfactor='90');


--
-- TOC entry 5117 (class 1259 OID 33629)
-- Name: bridge_lod1terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod1terr_spx ON citydb.bridge USING gist (lod1_terrain_intersection);


--
-- TOC entry 5118 (class 1259 OID 33630)
-- Name: bridge_lod2curve_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod2curve_spx ON citydb.bridge USING gist (lod2_multi_curve);


--
-- TOC entry 5119 (class 1259 OID 33631)
-- Name: bridge_lod2msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod2msrf_fkx ON citydb.bridge USING btree (lod2_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5120 (class 1259 OID 33632)
-- Name: bridge_lod2solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod2solid_fkx ON citydb.bridge USING btree (lod2_solid_id) WITH (fillfactor='90');


--
-- TOC entry 5121 (class 1259 OID 33633)
-- Name: bridge_lod2terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod2terr_spx ON citydb.bridge USING gist (lod2_terrain_intersection);


--
-- TOC entry 5122 (class 1259 OID 33634)
-- Name: bridge_lod3curve_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod3curve_spx ON citydb.bridge USING gist (lod3_multi_curve);


--
-- TOC entry 5123 (class 1259 OID 33635)
-- Name: bridge_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod3msrf_fkx ON citydb.bridge USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5124 (class 1259 OID 33636)
-- Name: bridge_lod3solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod3solid_fkx ON citydb.bridge USING btree (lod3_solid_id) WITH (fillfactor='90');


--
-- TOC entry 5125 (class 1259 OID 33637)
-- Name: bridge_lod3terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod3terr_spx ON citydb.bridge USING gist (lod3_terrain_intersection);


--
-- TOC entry 5126 (class 1259 OID 33638)
-- Name: bridge_lod4curve_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod4curve_spx ON citydb.bridge USING gist (lod4_multi_curve);


--
-- TOC entry 5127 (class 1259 OID 33639)
-- Name: bridge_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod4msrf_fkx ON citydb.bridge USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5128 (class 1259 OID 33640)
-- Name: bridge_lod4solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod4solid_fkx ON citydb.bridge USING btree (lod4_solid_id) WITH (fillfactor='90');


--
-- TOC entry 5129 (class 1259 OID 33641)
-- Name: bridge_lod4terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_lod4terr_spx ON citydb.bridge USING gist (lod4_terrain_intersection);


--
-- TOC entry 5130 (class 1259 OID 33642)
-- Name: bridge_objectclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_objectclass_fkx ON citydb.bridge USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5188 (class 1259 OID 33643)
-- Name: bridge_open_address_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_open_address_fkx ON citydb.bridge_opening USING btree (address_id) WITH (fillfactor='90');


--
-- TOC entry 5189 (class 1259 OID 33644)
-- Name: bridge_open_lod3impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_open_lod3impl_fkx ON citydb.bridge_opening USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5190 (class 1259 OID 33645)
-- Name: bridge_open_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_open_lod3msrf_fkx ON citydb.bridge_opening USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5191 (class 1259 OID 33646)
-- Name: bridge_open_lod3refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_open_lod3refpt_spx ON citydb.bridge_opening USING gist (lod3_implicit_ref_point);


--
-- TOC entry 5192 (class 1259 OID 33647)
-- Name: bridge_open_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_open_lod4impl_fkx ON citydb.bridge_opening USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5193 (class 1259 OID 33648)
-- Name: bridge_open_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_open_lod4msrf_fkx ON citydb.bridge_opening USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5194 (class 1259 OID 33649)
-- Name: bridge_open_lod4refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_open_lod4refpt_spx ON citydb.bridge_opening USING gist (lod4_implicit_ref_point);


--
-- TOC entry 5195 (class 1259 OID 33650)
-- Name: bridge_open_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_open_objclass_fkx ON citydb.bridge_opening USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5131 (class 1259 OID 33651)
-- Name: bridge_parent_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_parent_fkx ON citydb.bridge USING btree (bridge_parent_id) WITH (fillfactor='90');


--
-- TOC entry 5198 (class 1259 OID 33652)
-- Name: bridge_room_bridge_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_room_bridge_fkx ON citydb.bridge_room USING btree (bridge_id) WITH (fillfactor='90');


--
-- TOC entry 5199 (class 1259 OID 33653)
-- Name: bridge_room_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_room_lod4msrf_fkx ON citydb.bridge_room USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5200 (class 1259 OID 33654)
-- Name: bridge_room_lod4solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_room_lod4solid_fkx ON citydb.bridge_room USING btree (lod4_solid_id) WITH (fillfactor='90');


--
-- TOC entry 5201 (class 1259 OID 33655)
-- Name: bridge_room_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_room_objclass_fkx ON citydb.bridge_room USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5134 (class 1259 OID 33656)
-- Name: bridge_root_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX bridge_root_fkx ON citydb.bridge USING btree (bridge_root_id) WITH (fillfactor='90');


--
-- TOC entry 5214 (class 1259 OID 33657)
-- Name: building_lod0footprint_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod0footprint_fkx ON citydb.building USING btree (lod0_footprint_id) WITH (fillfactor='90');


--
-- TOC entry 5215 (class 1259 OID 33658)
-- Name: building_lod0roofprint_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod0roofprint_fkx ON citydb.building USING btree (lod0_roofprint_id) WITH (fillfactor='90');


--
-- TOC entry 5216 (class 1259 OID 33659)
-- Name: building_lod1msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod1msrf_fkx ON citydb.building USING btree (lod1_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5217 (class 1259 OID 33660)
-- Name: building_lod1solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod1solid_fkx ON citydb.building USING btree (lod1_solid_id) WITH (fillfactor='90');


--
-- TOC entry 5218 (class 1259 OID 33661)
-- Name: building_lod1terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod1terr_spx ON citydb.building USING gist (lod1_terrain_intersection);


--
-- TOC entry 5219 (class 1259 OID 33662)
-- Name: building_lod2curve_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod2curve_spx ON citydb.building USING gist (lod2_multi_curve);


--
-- TOC entry 5220 (class 1259 OID 33663)
-- Name: building_lod2msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod2msrf_fkx ON citydb.building USING btree (lod2_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5221 (class 1259 OID 33664)
-- Name: building_lod2solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod2solid_fkx ON citydb.building USING btree (lod2_solid_id) WITH (fillfactor='90');


--
-- TOC entry 5222 (class 1259 OID 33665)
-- Name: building_lod2terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod2terr_spx ON citydb.building USING gist (lod2_terrain_intersection);


--
-- TOC entry 5223 (class 1259 OID 33666)
-- Name: building_lod3curve_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod3curve_spx ON citydb.building USING gist (lod3_multi_curve);


--
-- TOC entry 5224 (class 1259 OID 33667)
-- Name: building_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod3msrf_fkx ON citydb.building USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5225 (class 1259 OID 33668)
-- Name: building_lod3solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod3solid_fkx ON citydb.building USING btree (lod3_solid_id) WITH (fillfactor='90');


--
-- TOC entry 5226 (class 1259 OID 33669)
-- Name: building_lod3terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod3terr_spx ON citydb.building USING gist (lod3_terrain_intersection);


--
-- TOC entry 5227 (class 1259 OID 33670)
-- Name: building_lod4curve_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod4curve_spx ON citydb.building USING gist (lod4_multi_curve);


--
-- TOC entry 5228 (class 1259 OID 33671)
-- Name: building_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod4msrf_fkx ON citydb.building USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5229 (class 1259 OID 33672)
-- Name: building_lod4solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod4solid_fkx ON citydb.building USING btree (lod4_solid_id) WITH (fillfactor='90');


--
-- TOC entry 5230 (class 1259 OID 33673)
-- Name: building_lod4terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_lod4terr_spx ON citydb.building USING gist (lod4_terrain_intersection);


--
-- TOC entry 5231 (class 1259 OID 33674)
-- Name: building_objectclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_objectclass_fkx ON citydb.building USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5232 (class 1259 OID 33675)
-- Name: building_parent_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_parent_fkx ON citydb.building USING btree (building_parent_id) WITH (fillfactor='90');


--
-- TOC entry 5235 (class 1259 OID 33676)
-- Name: building_root_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX building_root_fkx ON citydb.building USING btree (building_root_id) WITH (fillfactor='90');


--
-- TOC entry 5261 (class 1259 OID 33677)
-- Name: city_furn_lod1brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod1brep_fkx ON citydb.city_furniture USING btree (lod1_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5262 (class 1259 OID 33678)
-- Name: city_furn_lod1impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod1impl_fkx ON citydb.city_furniture USING btree (lod1_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5263 (class 1259 OID 33679)
-- Name: city_furn_lod1refpnt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod1refpnt_spx ON citydb.city_furniture USING gist (lod1_implicit_ref_point);


--
-- TOC entry 5264 (class 1259 OID 33680)
-- Name: city_furn_lod1terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod1terr_spx ON citydb.city_furniture USING gist (lod1_terrain_intersection);


--
-- TOC entry 5265 (class 1259 OID 33681)
-- Name: city_furn_lod1xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod1xgeom_spx ON citydb.city_furniture USING gist (lod1_other_geom);


--
-- TOC entry 5266 (class 1259 OID 33682)
-- Name: city_furn_lod2brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod2brep_fkx ON citydb.city_furniture USING btree (lod2_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5267 (class 1259 OID 33683)
-- Name: city_furn_lod2impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod2impl_fkx ON citydb.city_furniture USING btree (lod2_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5268 (class 1259 OID 33684)
-- Name: city_furn_lod2refpnt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod2refpnt_spx ON citydb.city_furniture USING gist (lod2_implicit_ref_point);


--
-- TOC entry 5269 (class 1259 OID 33685)
-- Name: city_furn_lod2terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod2terr_spx ON citydb.city_furniture USING gist (lod2_terrain_intersection);


--
-- TOC entry 5270 (class 1259 OID 33686)
-- Name: city_furn_lod2xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod2xgeom_spx ON citydb.city_furniture USING gist (lod2_other_geom);


--
-- TOC entry 5271 (class 1259 OID 33687)
-- Name: city_furn_lod3brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod3brep_fkx ON citydb.city_furniture USING btree (lod3_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5272 (class 1259 OID 33688)
-- Name: city_furn_lod3impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod3impl_fkx ON citydb.city_furniture USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5273 (class 1259 OID 33689)
-- Name: city_furn_lod3refpnt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod3refpnt_spx ON citydb.city_furniture USING gist (lod3_implicit_ref_point);


--
-- TOC entry 5274 (class 1259 OID 33690)
-- Name: city_furn_lod3terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod3terr_spx ON citydb.city_furniture USING gist (lod3_terrain_intersection);


--
-- TOC entry 5275 (class 1259 OID 33691)
-- Name: city_furn_lod3xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod3xgeom_spx ON citydb.city_furniture USING gist (lod3_other_geom);


--
-- TOC entry 5276 (class 1259 OID 33692)
-- Name: city_furn_lod4brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod4brep_fkx ON citydb.city_furniture USING btree (lod4_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5277 (class 1259 OID 33693)
-- Name: city_furn_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod4impl_fkx ON citydb.city_furniture USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5278 (class 1259 OID 33694)
-- Name: city_furn_lod4refpnt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod4refpnt_spx ON citydb.city_furniture USING gist (lod4_implicit_ref_point);


--
-- TOC entry 5279 (class 1259 OID 33695)
-- Name: city_furn_lod4terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod4terr_spx ON citydb.city_furniture USING gist (lod4_terrain_intersection);


--
-- TOC entry 5280 (class 1259 OID 33696)
-- Name: city_furn_lod4xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_lod4xgeom_spx ON citydb.city_furniture USING gist (lod4_other_geom);


--
-- TOC entry 5281 (class 1259 OID 33697)
-- Name: city_furn_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX city_furn_objclass_fkx ON citydb.city_furniture USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5284 (class 1259 OID 33698)
-- Name: citymodel_envelope_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX citymodel_envelope_spx ON citydb.citymodel USING gist (envelope);


--
-- TOC entry 5285 (class 1259 OID 33699)
-- Name: citymodel_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX citymodel_inx ON citydb.citymodel USING btree (gmlid, gmlid_codespace);


--
-- TOC entry 5288 (class 1259 OID 33700)
-- Name: cityobj_creation_date_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX cityobj_creation_date_inx ON citydb.cityobject USING btree (creation_date) WITH (fillfactor='90');


--
-- TOC entry 5289 (class 1259 OID 33701)
-- Name: cityobj_last_mod_date_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX cityobj_last_mod_date_inx ON citydb.cityobject USING btree (last_modification_date) WITH (fillfactor='90');


--
-- TOC entry 5290 (class 1259 OID 33702)
-- Name: cityobj_term_date_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX cityobj_term_date_inx ON citydb.cityobject USING btree (termination_date) WITH (fillfactor='90');


--
-- TOC entry 5291 (class 1259 OID 33703)
-- Name: cityobject_envelope_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX cityobject_envelope_spx ON citydb.cityobject USING gist (envelope);


--
-- TOC entry 5292 (class 1259 OID 33704)
-- Name: cityobject_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX cityobject_inx ON citydb.cityobject USING btree (gmlid, gmlid_codespace) WITH (fillfactor='90');


--
-- TOC entry 5293 (class 1259 OID 33705)
-- Name: cityobject_lineage_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX cityobject_lineage_inx ON citydb.cityobject USING btree (lineage);


--
-- TOC entry 5303 (class 1259 OID 33706)
-- Name: cityobject_member_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX cityobject_member_fkx ON citydb.cityobject_member USING btree (cityobject_id) WITH (fillfactor='90');


--
-- TOC entry 5304 (class 1259 OID 33707)
-- Name: cityobject_member_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX cityobject_member_fkx1 ON citydb.cityobject_member USING btree (citymodel_id) WITH (fillfactor='90');


--
-- TOC entry 5294 (class 1259 OID 33708)
-- Name: cityobject_objectclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX cityobject_objectclass_fkx ON citydb.cityobject USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5315 (class 1259 OID 33709)
-- Name: ext_ref_cityobject_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX ext_ref_cityobject_fkx ON citydb.external_reference USING btree (cityobject_id) WITH (fillfactor='90');


--
-- TOC entry 5322 (class 1259 OID 33710)
-- Name: gen_object_lod0brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod0brep_fkx ON citydb.generic_cityobject USING btree (lod0_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5323 (class 1259 OID 33711)
-- Name: gen_object_lod0impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod0impl_fkx ON citydb.generic_cityobject USING btree (lod0_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5324 (class 1259 OID 33712)
-- Name: gen_object_lod0refpnt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod0refpnt_spx ON citydb.generic_cityobject USING gist (lod0_implicit_ref_point);


--
-- TOC entry 5325 (class 1259 OID 33713)
-- Name: gen_object_lod0terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod0terr_spx ON citydb.generic_cityobject USING gist (lod0_terrain_intersection);


--
-- TOC entry 5326 (class 1259 OID 33714)
-- Name: gen_object_lod0xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod0xgeom_spx ON citydb.generic_cityobject USING gist (lod0_other_geom);


--
-- TOC entry 5327 (class 1259 OID 33715)
-- Name: gen_object_lod1brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod1brep_fkx ON citydb.generic_cityobject USING btree (lod1_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5328 (class 1259 OID 33716)
-- Name: gen_object_lod1impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod1impl_fkx ON citydb.generic_cityobject USING btree (lod1_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5329 (class 1259 OID 33717)
-- Name: gen_object_lod1refpnt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod1refpnt_spx ON citydb.generic_cityobject USING gist (lod1_implicit_ref_point);


--
-- TOC entry 5330 (class 1259 OID 33718)
-- Name: gen_object_lod1terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod1terr_spx ON citydb.generic_cityobject USING gist (lod1_terrain_intersection);


--
-- TOC entry 5331 (class 1259 OID 33719)
-- Name: gen_object_lod1xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod1xgeom_spx ON citydb.generic_cityobject USING gist (lod1_other_geom);


--
-- TOC entry 5332 (class 1259 OID 33720)
-- Name: gen_object_lod2brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod2brep_fkx ON citydb.generic_cityobject USING btree (lod2_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5333 (class 1259 OID 33721)
-- Name: gen_object_lod2impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod2impl_fkx ON citydb.generic_cityobject USING btree (lod2_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5334 (class 1259 OID 33722)
-- Name: gen_object_lod2refpnt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod2refpnt_spx ON citydb.generic_cityobject USING gist (lod2_implicit_ref_point);


--
-- TOC entry 5335 (class 1259 OID 33723)
-- Name: gen_object_lod2terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod2terr_spx ON citydb.generic_cityobject USING gist (lod2_terrain_intersection);


--
-- TOC entry 5336 (class 1259 OID 33724)
-- Name: gen_object_lod2xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod2xgeom_spx ON citydb.generic_cityobject USING gist (lod2_other_geom);


--
-- TOC entry 5337 (class 1259 OID 33725)
-- Name: gen_object_lod3brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod3brep_fkx ON citydb.generic_cityobject USING btree (lod3_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5338 (class 1259 OID 33726)
-- Name: gen_object_lod3impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod3impl_fkx ON citydb.generic_cityobject USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5339 (class 1259 OID 33727)
-- Name: gen_object_lod3refpnt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod3refpnt_spx ON citydb.generic_cityobject USING gist (lod3_implicit_ref_point);


--
-- TOC entry 5340 (class 1259 OID 33728)
-- Name: gen_object_lod3terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod3terr_spx ON citydb.generic_cityobject USING gist (lod3_terrain_intersection);


--
-- TOC entry 5341 (class 1259 OID 33729)
-- Name: gen_object_lod3xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod3xgeom_spx ON citydb.generic_cityobject USING gist (lod3_other_geom);


--
-- TOC entry 5342 (class 1259 OID 33730)
-- Name: gen_object_lod4brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod4brep_fkx ON citydb.generic_cityobject USING btree (lod4_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5343 (class 1259 OID 33731)
-- Name: gen_object_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod4impl_fkx ON citydb.generic_cityobject USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5344 (class 1259 OID 33732)
-- Name: gen_object_lod4refpnt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod4refpnt_spx ON citydb.generic_cityobject USING gist (lod4_implicit_ref_point);


--
-- TOC entry 5345 (class 1259 OID 33733)
-- Name: gen_object_lod4terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod4terr_spx ON citydb.generic_cityobject USING gist (lod4_terrain_intersection);


--
-- TOC entry 5346 (class 1259 OID 33734)
-- Name: gen_object_lod4xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_lod4xgeom_spx ON citydb.generic_cityobject USING gist (lod4_other_geom);


--
-- TOC entry 5347 (class 1259 OID 33735)
-- Name: gen_object_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX gen_object_objclass_fkx ON citydb.generic_cityobject USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5318 (class 1259 OID 33736)
-- Name: general_cityobject_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX general_cityobject_fkx ON citydb.generalization USING btree (cityobject_id) WITH (fillfactor='90');


--
-- TOC entry 5319 (class 1259 OID 33737)
-- Name: general_generalizes_to_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX general_generalizes_to_fkx ON citydb.generalization USING btree (generalizes_to_id) WITH (fillfactor='90');


--
-- TOC entry 5299 (class 1259 OID 33738)
-- Name: genericattrib_cityobj_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX genericattrib_cityobj_fkx ON citydb.cityobject_genericattrib USING btree (cityobject_id) WITH (fillfactor='90');


--
-- TOC entry 5300 (class 1259 OID 33739)
-- Name: genericattrib_geom_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX genericattrib_geom_fkx ON citydb.cityobject_genericattrib USING btree (surface_geometry_id) WITH (fillfactor='90');


--
-- TOC entry 5301 (class 1259 OID 33740)
-- Name: genericattrib_parent_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX genericattrib_parent_fkx ON citydb.cityobject_genericattrib USING btree (parent_genattrib_id) WITH (fillfactor='90');


--
-- TOC entry 5302 (class 1259 OID 33741)
-- Name: genericattrib_root_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX genericattrib_root_fkx ON citydb.cityobject_genericattrib USING btree (root_genattrib_id) WITH (fillfactor='90');


--
-- TOC entry 5352 (class 1259 OID 33742)
-- Name: grid_coverage_raster_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX grid_coverage_raster_spx ON citydb.grid_coverage USING gist (public.st_convexhull(rasterproperty));


--
-- TOC entry 5309 (class 1259 OID 33743)
-- Name: group_brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX group_brep_fkx ON citydb.cityobjectgroup USING btree (brep_id) WITH (fillfactor='90');


--
-- TOC entry 5310 (class 1259 OID 33744)
-- Name: group_objectclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX group_objectclass_fkx ON citydb.cityobjectgroup USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5311 (class 1259 OID 33745)
-- Name: group_parent_cityobj_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX group_parent_cityobj_fkx ON citydb.cityobjectgroup USING btree (parent_cityobject_id) WITH (fillfactor='90');


--
-- TOC entry 5353 (class 1259 OID 33746)
-- Name: group_to_cityobject_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX group_to_cityobject_fkx ON citydb.group_to_cityobject USING btree (cityobject_id) WITH (fillfactor='90');


--
-- TOC entry 5354 (class 1259 OID 33747)
-- Name: group_to_cityobject_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX group_to_cityobject_fkx1 ON citydb.group_to_cityobject USING btree (cityobjectgroup_id) WITH (fillfactor='90');


--
-- TOC entry 5312 (class 1259 OID 33748)
-- Name: group_xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX group_xgeom_spx ON citydb.cityobjectgroup USING gist (other_geom);


--
-- TOC entry 5357 (class 1259 OID 33749)
-- Name: implicit_geom_brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX implicit_geom_brep_fkx ON citydb.implicit_geometry USING btree (relative_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5358 (class 1259 OID 33750)
-- Name: implicit_geom_ref2lib_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX implicit_geom_ref2lib_inx ON citydb.implicit_geometry USING btree (reference_to_library) WITH (fillfactor='90');


--
-- TOC entry 5363 (class 1259 OID 33751)
-- Name: land_use_lod0msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX land_use_lod0msrf_fkx ON citydb.land_use USING btree (lod0_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5364 (class 1259 OID 33752)
-- Name: land_use_lod1msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX land_use_lod1msrf_fkx ON citydb.land_use USING btree (lod1_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5365 (class 1259 OID 33753)
-- Name: land_use_lod2msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX land_use_lod2msrf_fkx ON citydb.land_use USING btree (lod2_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5366 (class 1259 OID 33754)
-- Name: land_use_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX land_use_lod3msrf_fkx ON citydb.land_use USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5367 (class 1259 OID 33755)
-- Name: land_use_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX land_use_lod4msrf_fkx ON citydb.land_use USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5368 (class 1259 OID 33756)
-- Name: land_use_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX land_use_objclass_fkx ON citydb.land_use USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5371 (class 1259 OID 33757)
-- Name: masspoint_rel_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX masspoint_rel_objclass_fkx ON citydb.masspoint_relief USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5374 (class 1259 OID 33758)
-- Name: masspoint_relief_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX masspoint_relief_spx ON citydb.masspoint_relief USING gist (relief_points);


--
-- TOC entry 5375 (class 1259 OID 33759)
-- Name: objectclass_baseclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX objectclass_baseclass_fkx ON citydb.objectclass USING btree (baseclass_id) WITH (fillfactor='90');


--
-- TOC entry 5378 (class 1259 OID 33760)
-- Name: objectclass_superclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX objectclass_superclass_fkx ON citydb.objectclass USING btree (superclass_id) WITH (fillfactor='90');


--
-- TOC entry 5389 (class 1259 OID 33761)
-- Name: open_to_them_surface_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX open_to_them_surface_fkx ON citydb.opening_to_them_surface USING btree (opening_id) WITH (fillfactor='90');


--
-- TOC entry 5390 (class 1259 OID 33762)
-- Name: open_to_them_surface_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX open_to_them_surface_fkx1 ON citydb.opening_to_them_surface USING btree (thematic_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5379 (class 1259 OID 33763)
-- Name: opening_address_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX opening_address_fkx ON citydb.opening USING btree (address_id) WITH (fillfactor='90');


--
-- TOC entry 5380 (class 1259 OID 33764)
-- Name: opening_lod3impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX opening_lod3impl_fkx ON citydb.opening USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5381 (class 1259 OID 33765)
-- Name: opening_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX opening_lod3msrf_fkx ON citydb.opening USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5382 (class 1259 OID 33766)
-- Name: opening_lod3refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX opening_lod3refpt_spx ON citydb.opening USING gist (lod3_implicit_ref_point);


--
-- TOC entry 5383 (class 1259 OID 33767)
-- Name: opening_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX opening_lod4impl_fkx ON citydb.opening USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5384 (class 1259 OID 33768)
-- Name: opening_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX opening_lod4msrf_fkx ON citydb.opening USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5385 (class 1259 OID 33769)
-- Name: opening_lod4refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX opening_lod4refpt_spx ON citydb.opening USING gist (lod4_implicit_ref_point);


--
-- TOC entry 5386 (class 1259 OID 33770)
-- Name: opening_objectclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX opening_objectclass_fkx ON citydb.opening USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5393 (class 1259 OID 33771)
-- Name: plant_cover_lod1msolid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX plant_cover_lod1msolid_fkx ON citydb.plant_cover USING btree (lod1_multi_solid_id) WITH (fillfactor='90');


--
-- TOC entry 5394 (class 1259 OID 33772)
-- Name: plant_cover_lod1msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX plant_cover_lod1msrf_fkx ON citydb.plant_cover USING btree (lod1_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5395 (class 1259 OID 33773)
-- Name: plant_cover_lod2msolid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX plant_cover_lod2msolid_fkx ON citydb.plant_cover USING btree (lod2_multi_solid_id) WITH (fillfactor='90');


--
-- TOC entry 5396 (class 1259 OID 33774)
-- Name: plant_cover_lod2msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX plant_cover_lod2msrf_fkx ON citydb.plant_cover USING btree (lod2_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5397 (class 1259 OID 33775)
-- Name: plant_cover_lod3msolid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX plant_cover_lod3msolid_fkx ON citydb.plant_cover USING btree (lod3_multi_solid_id) WITH (fillfactor='90');


--
-- TOC entry 5398 (class 1259 OID 33776)
-- Name: plant_cover_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX plant_cover_lod3msrf_fkx ON citydb.plant_cover USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5399 (class 1259 OID 33777)
-- Name: plant_cover_lod4msolid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX plant_cover_lod4msolid_fkx ON citydb.plant_cover USING btree (lod4_multi_solid_id) WITH (fillfactor='90');


--
-- TOC entry 5400 (class 1259 OID 33778)
-- Name: plant_cover_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX plant_cover_lod4msrf_fkx ON citydb.plant_cover USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5401 (class 1259 OID 33779)
-- Name: plant_cover_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX plant_cover_objclass_fkx ON citydb.plant_cover USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5404 (class 1259 OID 33780)
-- Name: raster_relief_coverage_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX raster_relief_coverage_fkx ON citydb.raster_relief USING btree (coverage_id) WITH (fillfactor='90');


--
-- TOC entry 5405 (class 1259 OID 33781)
-- Name: raster_relief_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX raster_relief_objclass_fkx ON citydb.raster_relief USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5412 (class 1259 OID 33782)
-- Name: rel_feat_to_rel_comp_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX rel_feat_to_rel_comp_fkx ON citydb.relief_feat_to_rel_comp USING btree (relief_component_id) WITH (fillfactor='90');


--
-- TOC entry 5413 (class 1259 OID 33783)
-- Name: rel_feat_to_rel_comp_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX rel_feat_to_rel_comp_fkx1 ON citydb.relief_feat_to_rel_comp USING btree (relief_feature_id) WITH (fillfactor='90');


--
-- TOC entry 5408 (class 1259 OID 33784)
-- Name: relief_comp_extent_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX relief_comp_extent_spx ON citydb.relief_component USING gist (extent);


--
-- TOC entry 5409 (class 1259 OID 33785)
-- Name: relief_comp_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX relief_comp_objclass_fkx ON citydb.relief_component USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5416 (class 1259 OID 33786)
-- Name: relief_feat_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX relief_feat_objclass_fkx ON citydb.relief_feature USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5419 (class 1259 OID 33787)
-- Name: room_building_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX room_building_fkx ON citydb.room USING btree (building_id) WITH (fillfactor='90');


--
-- TOC entry 5420 (class 1259 OID 33788)
-- Name: room_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX room_lod4msrf_fkx ON citydb.room USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5421 (class 1259 OID 33789)
-- Name: room_lod4solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX room_lod4solid_fkx ON citydb.room USING btree (lod4_solid_id) WITH (fillfactor='90');


--
-- TOC entry 5422 (class 1259 OID 33790)
-- Name: room_objectclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX room_objectclass_fkx ON citydb.room USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5427 (class 1259 OID 33791)
-- Name: schema_referencing_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX schema_referencing_fkx1 ON citydb.schema_referencing USING btree (referenced_id) WITH (fillfactor='90');


--
-- TOC entry 5428 (class 1259 OID 33792)
-- Name: schema_referencing_fkx2; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX schema_referencing_fkx2 ON citydb.schema_referencing USING btree (referencing_id) WITH (fillfactor='90');


--
-- TOC entry 5431 (class 1259 OID 33793)
-- Name: schema_to_objectclass_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX schema_to_objectclass_fkx1 ON citydb.schema_to_objectclass USING btree (schema_id) WITH (fillfactor='90');


--
-- TOC entry 5432 (class 1259 OID 33794)
-- Name: schema_to_objectclass_fkx2; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX schema_to_objectclass_fkx2 ON citydb.schema_to_objectclass USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5435 (class 1259 OID 33795)
-- Name: sol_veg_obj_lod1brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod1brep_fkx ON citydb.solitary_vegetat_object USING btree (lod1_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5436 (class 1259 OID 33796)
-- Name: sol_veg_obj_lod1impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod1impl_fkx ON citydb.solitary_vegetat_object USING btree (lod1_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5437 (class 1259 OID 33797)
-- Name: sol_veg_obj_lod1refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod1refpt_spx ON citydb.solitary_vegetat_object USING gist (lod1_implicit_ref_point);


--
-- TOC entry 5438 (class 1259 OID 33798)
-- Name: sol_veg_obj_lod1xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod1xgeom_spx ON citydb.solitary_vegetat_object USING gist (lod1_other_geom);


--
-- TOC entry 5439 (class 1259 OID 33799)
-- Name: sol_veg_obj_lod2brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod2brep_fkx ON citydb.solitary_vegetat_object USING btree (lod2_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5440 (class 1259 OID 33800)
-- Name: sol_veg_obj_lod2impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod2impl_fkx ON citydb.solitary_vegetat_object USING btree (lod2_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5441 (class 1259 OID 33801)
-- Name: sol_veg_obj_lod2refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod2refpt_spx ON citydb.solitary_vegetat_object USING gist (lod2_implicit_ref_point);


--
-- TOC entry 5442 (class 1259 OID 33802)
-- Name: sol_veg_obj_lod2xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod2xgeom_spx ON citydb.solitary_vegetat_object USING gist (lod2_other_geom);


--
-- TOC entry 5443 (class 1259 OID 33803)
-- Name: sol_veg_obj_lod3brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod3brep_fkx ON citydb.solitary_vegetat_object USING btree (lod3_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5444 (class 1259 OID 33804)
-- Name: sol_veg_obj_lod3impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod3impl_fkx ON citydb.solitary_vegetat_object USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5445 (class 1259 OID 33805)
-- Name: sol_veg_obj_lod3refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod3refpt_spx ON citydb.solitary_vegetat_object USING gist (lod3_implicit_ref_point);


--
-- TOC entry 5446 (class 1259 OID 33806)
-- Name: sol_veg_obj_lod3xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod3xgeom_spx ON citydb.solitary_vegetat_object USING gist (lod3_other_geom);


--
-- TOC entry 5447 (class 1259 OID 33807)
-- Name: sol_veg_obj_lod4brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod4brep_fkx ON citydb.solitary_vegetat_object USING btree (lod4_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5448 (class 1259 OID 33808)
-- Name: sol_veg_obj_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod4impl_fkx ON citydb.solitary_vegetat_object USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5449 (class 1259 OID 33809)
-- Name: sol_veg_obj_lod4refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod4refpt_spx ON citydb.solitary_vegetat_object USING gist (lod4_implicit_ref_point);


--
-- TOC entry 5450 (class 1259 OID 33810)
-- Name: sol_veg_obj_lod4xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_lod4xgeom_spx ON citydb.solitary_vegetat_object USING gist (lod4_other_geom);


--
-- TOC entry 5451 (class 1259 OID 33811)
-- Name: sol_veg_obj_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX sol_veg_obj_objclass_fkx ON citydb.solitary_vegetat_object USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5454 (class 1259 OID 33812)
-- Name: surface_data_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX surface_data_inx ON citydb.surface_data USING btree (gmlid, gmlid_codespace) WITH (fillfactor='90');


--
-- TOC entry 5455 (class 1259 OID 33813)
-- Name: surface_data_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX surface_data_objclass_fkx ON citydb.surface_data USING btree (objectclass_id);


--
-- TOC entry 5458 (class 1259 OID 33814)
-- Name: surface_data_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX surface_data_spx ON citydb.surface_data USING gist (gt_reference_point);


--
-- TOC entry 5459 (class 1259 OID 33815)
-- Name: surface_data_tex_image_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX surface_data_tex_image_fkx ON citydb.surface_data USING btree (tex_image_id);


--
-- TOC entry 5460 (class 1259 OID 33816)
-- Name: surface_geom_cityobj_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX surface_geom_cityobj_fkx ON citydb.surface_geometry USING btree (cityobject_id) WITH (fillfactor='90');


--
-- TOC entry 5461 (class 1259 OID 33817)
-- Name: surface_geom_inx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX surface_geom_inx ON citydb.surface_geometry USING btree (gmlid, gmlid_codespace) WITH (fillfactor='90');


--
-- TOC entry 5462 (class 1259 OID 33818)
-- Name: surface_geom_parent_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX surface_geom_parent_fkx ON citydb.surface_geometry USING btree (parent_id) WITH (fillfactor='90');


--
-- TOC entry 5463 (class 1259 OID 33819)
-- Name: surface_geom_root_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX surface_geom_root_fkx ON citydb.surface_geometry USING btree (root_id) WITH (fillfactor='90');


--
-- TOC entry 5464 (class 1259 OID 33820)
-- Name: surface_geom_solid_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX surface_geom_solid_spx ON citydb.surface_geometry USING gist (solid_geometry);


--
-- TOC entry 5465 (class 1259 OID 33821)
-- Name: surface_geom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX surface_geom_spx ON citydb.surface_geometry USING gist (geometry);


--
-- TOC entry 5470 (class 1259 OID 33822)
-- Name: texparam_geom_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX texparam_geom_fkx ON citydb.textureparam USING btree (surface_geometry_id) WITH (fillfactor='90');


--
-- TOC entry 5471 (class 1259 OID 33823)
-- Name: texparam_surface_data_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX texparam_surface_data_fkx ON citydb.textureparam USING btree (surface_data_id) WITH (fillfactor='90');


--
-- TOC entry 5474 (class 1259 OID 33824)
-- Name: them_surface_bldg_inst_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX them_surface_bldg_inst_fkx ON citydb.thematic_surface USING btree (building_installation_id) WITH (fillfactor='90');


--
-- TOC entry 5475 (class 1259 OID 33825)
-- Name: them_surface_building_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX them_surface_building_fkx ON citydb.thematic_surface USING btree (building_id) WITH (fillfactor='90');


--
-- TOC entry 5476 (class 1259 OID 33826)
-- Name: them_surface_lod2msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX them_surface_lod2msrf_fkx ON citydb.thematic_surface USING btree (lod2_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5477 (class 1259 OID 33827)
-- Name: them_surface_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX them_surface_lod3msrf_fkx ON citydb.thematic_surface USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5478 (class 1259 OID 33828)
-- Name: them_surface_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX them_surface_lod4msrf_fkx ON citydb.thematic_surface USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5479 (class 1259 OID 33829)
-- Name: them_surface_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX them_surface_objclass_fkx ON citydb.thematic_surface USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5480 (class 1259 OID 33830)
-- Name: them_surface_room_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX them_surface_room_fkx ON citydb.thematic_surface USING btree (room_id) WITH (fillfactor='90');


--
-- TOC entry 5483 (class 1259 OID 33831)
-- Name: tin_relief_break_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tin_relief_break_spx ON citydb.tin_relief USING gist (break_lines);


--
-- TOC entry 5484 (class 1259 OID 33832)
-- Name: tin_relief_crtlpts_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tin_relief_crtlpts_spx ON citydb.tin_relief USING gist (control_points);


--
-- TOC entry 5485 (class 1259 OID 33833)
-- Name: tin_relief_geom_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tin_relief_geom_fkx ON citydb.tin_relief USING btree (surface_geometry_id) WITH (fillfactor='90');


--
-- TOC entry 5486 (class 1259 OID 33834)
-- Name: tin_relief_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tin_relief_objclass_fkx ON citydb.tin_relief USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5489 (class 1259 OID 33835)
-- Name: tin_relief_stop_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tin_relief_stop_spx ON citydb.tin_relief USING gist (stop_lines);


--
-- TOC entry 5490 (class 1259 OID 33836)
-- Name: traffic_area_lod2msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX traffic_area_lod2msrf_fkx ON citydb.traffic_area USING btree (lod2_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5491 (class 1259 OID 33837)
-- Name: traffic_area_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX traffic_area_lod3msrf_fkx ON citydb.traffic_area USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5492 (class 1259 OID 33838)
-- Name: traffic_area_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX traffic_area_lod4msrf_fkx ON citydb.traffic_area USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5493 (class 1259 OID 33839)
-- Name: traffic_area_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX traffic_area_objclass_fkx ON citydb.traffic_area USING btree (objectclass_id);


--
-- TOC entry 5496 (class 1259 OID 33840)
-- Name: traffic_area_trancmplx_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX traffic_area_trancmplx_fkx ON citydb.traffic_area USING btree (transportation_complex_id) WITH (fillfactor='90');


--
-- TOC entry 5497 (class 1259 OID 33841)
-- Name: tran_complex_lod0net_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tran_complex_lod0net_spx ON citydb.transportation_complex USING gist (lod0_network);


--
-- TOC entry 5498 (class 1259 OID 33842)
-- Name: tran_complex_lod1msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tran_complex_lod1msrf_fkx ON citydb.transportation_complex USING btree (lod1_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5499 (class 1259 OID 33843)
-- Name: tran_complex_lod2msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tran_complex_lod2msrf_fkx ON citydb.transportation_complex USING btree (lod2_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5500 (class 1259 OID 33844)
-- Name: tran_complex_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tran_complex_lod3msrf_fkx ON citydb.transportation_complex USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5501 (class 1259 OID 33845)
-- Name: tran_complex_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tran_complex_lod4msrf_fkx ON citydb.transportation_complex USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5502 (class 1259 OID 33846)
-- Name: tran_complex_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tran_complex_objclass_fkx ON citydb.transportation_complex USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5533 (class 1259 OID 33847)
-- Name: tun_hspace_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_hspace_lod4msrf_fkx ON citydb.tunnel_hollow_space USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5534 (class 1259 OID 33848)
-- Name: tun_hspace_lod4solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_hspace_lod4solid_fkx ON citydb.tunnel_hollow_space USING btree (lod4_solid_id) WITH (fillfactor='90');


--
-- TOC entry 5535 (class 1259 OID 33849)
-- Name: tun_hspace_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_hspace_objclass_fkx ON citydb.tunnel_hollow_space USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5536 (class 1259 OID 33850)
-- Name: tun_hspace_tunnel_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_hspace_tunnel_fkx ON citydb.tunnel_hollow_space USING btree (tunnel_id) WITH (fillfactor='90');


--
-- TOC entry 5556 (class 1259 OID 33851)
-- Name: tun_open_to_them_srf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_open_to_them_srf_fkx ON citydb.tunnel_open_to_them_srf USING btree (tunnel_opening_id) WITH (fillfactor='90');


--
-- TOC entry 5557 (class 1259 OID 33852)
-- Name: tun_open_to_them_srf_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_open_to_them_srf_fkx1 ON citydb.tunnel_open_to_them_srf USING btree (tunnel_thematic_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5569 (class 1259 OID 33853)
-- Name: tun_them_srf_hspace_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_them_srf_hspace_fkx ON citydb.tunnel_thematic_surface USING btree (tunnel_hollow_space_id) WITH (fillfactor='90');


--
-- TOC entry 5570 (class 1259 OID 33854)
-- Name: tun_them_srf_lod2msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_them_srf_lod2msrf_fkx ON citydb.tunnel_thematic_surface USING btree (lod2_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5571 (class 1259 OID 33855)
-- Name: tun_them_srf_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_them_srf_lod3msrf_fkx ON citydb.tunnel_thematic_surface USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5572 (class 1259 OID 33856)
-- Name: tun_them_srf_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_them_srf_lod4msrf_fkx ON citydb.tunnel_thematic_surface USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5573 (class 1259 OID 33857)
-- Name: tun_them_srf_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_them_srf_objclass_fkx ON citydb.tunnel_thematic_surface USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5574 (class 1259 OID 33858)
-- Name: tun_them_srf_tun_inst_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_them_srf_tun_inst_fkx ON citydb.tunnel_thematic_surface USING btree (tunnel_installation_id) WITH (fillfactor='90');


--
-- TOC entry 5575 (class 1259 OID 33859)
-- Name: tun_them_srf_tunnel_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tun_them_srf_tunnel_fkx ON citydb.tunnel_thematic_surface USING btree (tunnel_id) WITH (fillfactor='90');


--
-- TOC entry 5525 (class 1259 OID 33860)
-- Name: tunnel_furn_hspace_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_furn_hspace_fkx ON citydb.tunnel_furniture USING btree (tunnel_hollow_space_id) WITH (fillfactor='90');


--
-- TOC entry 5526 (class 1259 OID 33861)
-- Name: tunnel_furn_lod4brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_furn_lod4brep_fkx ON citydb.tunnel_furniture USING btree (lod4_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5527 (class 1259 OID 33862)
-- Name: tunnel_furn_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_furn_lod4impl_fkx ON citydb.tunnel_furniture USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5528 (class 1259 OID 33863)
-- Name: tunnel_furn_lod4refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_furn_lod4refpt_spx ON citydb.tunnel_furniture USING gist (lod4_implicit_ref_point);


--
-- TOC entry 5529 (class 1259 OID 33864)
-- Name: tunnel_furn_lod4xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_furn_lod4xgeom_spx ON citydb.tunnel_furniture USING gist (lod4_other_geom);


--
-- TOC entry 5530 (class 1259 OID 33865)
-- Name: tunnel_furn_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_furn_objclass_fkx ON citydb.tunnel_furniture USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5539 (class 1259 OID 33866)
-- Name: tunnel_inst_hspace_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_hspace_fkx ON citydb.tunnel_installation USING btree (tunnel_hollow_space_id) WITH (fillfactor='90');


--
-- TOC entry 5540 (class 1259 OID 33867)
-- Name: tunnel_inst_lod2brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod2brep_fkx ON citydb.tunnel_installation USING btree (lod2_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5541 (class 1259 OID 33868)
-- Name: tunnel_inst_lod2impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod2impl_fkx ON citydb.tunnel_installation USING btree (lod2_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5542 (class 1259 OID 33869)
-- Name: tunnel_inst_lod2refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod2refpt_spx ON citydb.tunnel_installation USING gist (lod2_implicit_ref_point);


--
-- TOC entry 5543 (class 1259 OID 33870)
-- Name: tunnel_inst_lod2xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod2xgeom_spx ON citydb.tunnel_installation USING gist (lod2_other_geom);


--
-- TOC entry 5544 (class 1259 OID 33871)
-- Name: tunnel_inst_lod3brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod3brep_fkx ON citydb.tunnel_installation USING btree (lod3_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5545 (class 1259 OID 33872)
-- Name: tunnel_inst_lod3impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod3impl_fkx ON citydb.tunnel_installation USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5546 (class 1259 OID 33873)
-- Name: tunnel_inst_lod3refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod3refpt_spx ON citydb.tunnel_installation USING gist (lod3_implicit_ref_point);


--
-- TOC entry 5547 (class 1259 OID 33874)
-- Name: tunnel_inst_lod3xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod3xgeom_spx ON citydb.tunnel_installation USING gist (lod3_other_geom);


--
-- TOC entry 5548 (class 1259 OID 33875)
-- Name: tunnel_inst_lod4brep_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod4brep_fkx ON citydb.tunnel_installation USING btree (lod4_brep_id) WITH (fillfactor='90');


--
-- TOC entry 5549 (class 1259 OID 33876)
-- Name: tunnel_inst_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod4impl_fkx ON citydb.tunnel_installation USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5550 (class 1259 OID 33877)
-- Name: tunnel_inst_lod4refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod4refpt_spx ON citydb.tunnel_installation USING gist (lod4_implicit_ref_point);


--
-- TOC entry 5551 (class 1259 OID 33878)
-- Name: tunnel_inst_lod4xgeom_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_lod4xgeom_spx ON citydb.tunnel_installation USING gist (lod4_other_geom);


--
-- TOC entry 5552 (class 1259 OID 33879)
-- Name: tunnel_inst_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_objclass_fkx ON citydb.tunnel_installation USING btree (objectclass_id);


--
-- TOC entry 5553 (class 1259 OID 33880)
-- Name: tunnel_inst_tunnel_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_inst_tunnel_fkx ON citydb.tunnel_installation USING btree (tunnel_id) WITH (fillfactor='90');


--
-- TOC entry 5505 (class 1259 OID 33881)
-- Name: tunnel_lod1msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod1msrf_fkx ON citydb.tunnel USING btree (lod1_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5506 (class 1259 OID 33882)
-- Name: tunnel_lod1solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod1solid_fkx ON citydb.tunnel USING btree (lod1_solid_id) WITH (fillfactor='90');


--
-- TOC entry 5507 (class 1259 OID 33883)
-- Name: tunnel_lod1terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod1terr_spx ON citydb.tunnel USING gist (lod1_terrain_intersection);


--
-- TOC entry 5508 (class 1259 OID 33884)
-- Name: tunnel_lod2curve_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod2curve_spx ON citydb.tunnel USING gist (lod2_multi_curve);


--
-- TOC entry 5509 (class 1259 OID 33885)
-- Name: tunnel_lod2msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod2msrf_fkx ON citydb.tunnel USING btree (lod2_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5510 (class 1259 OID 33886)
-- Name: tunnel_lod2solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod2solid_fkx ON citydb.tunnel USING btree (lod2_solid_id) WITH (fillfactor='90');


--
-- TOC entry 5511 (class 1259 OID 33887)
-- Name: tunnel_lod2terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod2terr_spx ON citydb.tunnel USING gist (lod2_terrain_intersection);


--
-- TOC entry 5512 (class 1259 OID 33888)
-- Name: tunnel_lod3curve_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod3curve_spx ON citydb.tunnel USING gist (lod3_multi_curve);


--
-- TOC entry 5513 (class 1259 OID 33889)
-- Name: tunnel_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod3msrf_fkx ON citydb.tunnel USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5514 (class 1259 OID 33890)
-- Name: tunnel_lod3solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod3solid_fkx ON citydb.tunnel USING btree (lod3_solid_id) WITH (fillfactor='90');


--
-- TOC entry 5515 (class 1259 OID 33891)
-- Name: tunnel_lod3terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod3terr_spx ON citydb.tunnel USING gist (lod3_terrain_intersection);


--
-- TOC entry 5516 (class 1259 OID 33892)
-- Name: tunnel_lod4curve_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod4curve_spx ON citydb.tunnel USING gist (lod4_multi_curve);


--
-- TOC entry 5517 (class 1259 OID 33893)
-- Name: tunnel_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod4msrf_fkx ON citydb.tunnel USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5518 (class 1259 OID 33894)
-- Name: tunnel_lod4solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod4solid_fkx ON citydb.tunnel USING btree (lod4_solid_id) WITH (fillfactor='90');


--
-- TOC entry 5519 (class 1259 OID 33895)
-- Name: tunnel_lod4terr_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_lod4terr_spx ON citydb.tunnel USING gist (lod4_terrain_intersection);


--
-- TOC entry 5520 (class 1259 OID 33896)
-- Name: tunnel_objectclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_objectclass_fkx ON citydb.tunnel USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5560 (class 1259 OID 33897)
-- Name: tunnel_open_lod3impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_open_lod3impl_fkx ON citydb.tunnel_opening USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5561 (class 1259 OID 33898)
-- Name: tunnel_open_lod3msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_open_lod3msrf_fkx ON citydb.tunnel_opening USING btree (lod3_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5562 (class 1259 OID 33899)
-- Name: tunnel_open_lod3refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_open_lod3refpt_spx ON citydb.tunnel_opening USING gist (lod3_implicit_ref_point);


--
-- TOC entry 5563 (class 1259 OID 33900)
-- Name: tunnel_open_lod4impl_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_open_lod4impl_fkx ON citydb.tunnel_opening USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');


--
-- TOC entry 5564 (class 1259 OID 33901)
-- Name: tunnel_open_lod4msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_open_lod4msrf_fkx ON citydb.tunnel_opening USING btree (lod4_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5565 (class 1259 OID 33902)
-- Name: tunnel_open_lod4refpt_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_open_lod4refpt_spx ON citydb.tunnel_opening USING gist (lod4_implicit_ref_point);


--
-- TOC entry 5566 (class 1259 OID 33903)
-- Name: tunnel_open_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_open_objclass_fkx ON citydb.tunnel_opening USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5521 (class 1259 OID 33904)
-- Name: tunnel_parent_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_parent_fkx ON citydb.tunnel USING btree (tunnel_parent_id) WITH (fillfactor='90');


--
-- TOC entry 5524 (class 1259 OID 33905)
-- Name: tunnel_root_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX tunnel_root_fkx ON citydb.tunnel USING btree (tunnel_root_id) WITH (fillfactor='90');


--
-- TOC entry 5593 (class 1259 OID 33906)
-- Name: waterbnd_srf_lod2srf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbnd_srf_lod2srf_fkx ON citydb.waterboundary_surface USING btree (lod2_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5594 (class 1259 OID 33907)
-- Name: waterbnd_srf_lod3srf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbnd_srf_lod3srf_fkx ON citydb.waterboundary_surface USING btree (lod3_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5595 (class 1259 OID 33908)
-- Name: waterbnd_srf_lod4srf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbnd_srf_lod4srf_fkx ON citydb.waterboundary_surface USING btree (lod4_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5596 (class 1259 OID 33909)
-- Name: waterbnd_srf_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbnd_srf_objclass_fkx ON citydb.waterboundary_surface USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5578 (class 1259 OID 33910)
-- Name: waterbod_to_waterbnd_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbod_to_waterbnd_fkx ON citydb.waterbod_to_waterbnd_srf USING btree (waterboundary_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5579 (class 1259 OID 33911)
-- Name: waterbod_to_waterbnd_fkx1; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbod_to_waterbnd_fkx1 ON citydb.waterbod_to_waterbnd_srf USING btree (waterbody_id) WITH (fillfactor='90');


--
-- TOC entry 5582 (class 1259 OID 33912)
-- Name: waterbody_lod0curve_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbody_lod0curve_spx ON citydb.waterbody USING gist (lod0_multi_curve);


--
-- TOC entry 5583 (class 1259 OID 33913)
-- Name: waterbody_lod0msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbody_lod0msrf_fkx ON citydb.waterbody USING btree (lod0_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5584 (class 1259 OID 33914)
-- Name: waterbody_lod1curve_spx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbody_lod1curve_spx ON citydb.waterbody USING gist (lod1_multi_curve);


--
-- TOC entry 5585 (class 1259 OID 33915)
-- Name: waterbody_lod1msrf_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbody_lod1msrf_fkx ON citydb.waterbody USING btree (lod1_multi_surface_id) WITH (fillfactor='90');


--
-- TOC entry 5586 (class 1259 OID 33916)
-- Name: waterbody_lod1solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbody_lod1solid_fkx ON citydb.waterbody USING btree (lod1_solid_id) WITH (fillfactor='90');


--
-- TOC entry 5587 (class 1259 OID 33917)
-- Name: waterbody_lod2solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbody_lod2solid_fkx ON citydb.waterbody USING btree (lod2_solid_id) WITH (fillfactor='90');


--
-- TOC entry 5588 (class 1259 OID 33918)
-- Name: waterbody_lod3solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbody_lod3solid_fkx ON citydb.waterbody USING btree (lod3_solid_id) WITH (fillfactor='90');


--
-- TOC entry 5589 (class 1259 OID 33919)
-- Name: waterbody_lod4solid_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbody_lod4solid_fkx ON citydb.waterbody USING btree (lod4_solid_id) WITH (fillfactor='90');


--
-- TOC entry 5590 (class 1259 OID 33920)
-- Name: waterbody_objclass_fkx; Type: INDEX; Schema: citydb; Owner: postgres
--

CREATE INDEX waterbody_objclass_fkx ON citydb.waterbody USING btree (objectclass_id) WITH (fillfactor='90');


--
-- TOC entry 5599 (class 2606 OID 33921)
-- Name: address_to_bridge address_to_bridge_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.address_to_bridge
    ADD CONSTRAINT address_to_bridge_fk FOREIGN KEY (address_id) REFERENCES citydb.address(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5600 (class 2606 OID 33926)
-- Name: address_to_bridge address_to_bridge_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.address_to_bridge
    ADD CONSTRAINT address_to_bridge_fk1 FOREIGN KEY (bridge_id) REFERENCES citydb.bridge(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5601 (class 2606 OID 33931)
-- Name: address_to_building address_to_building_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.address_to_building
    ADD CONSTRAINT address_to_building_fk FOREIGN KEY (address_id) REFERENCES citydb.address(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5602 (class 2606 OID 33936)
-- Name: address_to_building address_to_building_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.address_to_building
    ADD CONSTRAINT address_to_building_fk1 FOREIGN KEY (building_id) REFERENCES citydb.building(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5603 (class 2606 OID 33941)
-- Name: aggregation_info aggregation_info_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.aggregation_info
    ADD CONSTRAINT aggregation_info_fk1 FOREIGN KEY (child_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5604 (class 2606 OID 33946)
-- Name: aggregation_info aggregation_info_fk2; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.aggregation_info
    ADD CONSTRAINT aggregation_info_fk2 FOREIGN KEY (parent_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5605 (class 2606 OID 33951)
-- Name: appear_to_surface_data app_to_surf_data_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.appear_to_surface_data
    ADD CONSTRAINT app_to_surf_data_fk FOREIGN KEY (surface_data_id) REFERENCES citydb.surface_data(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5606 (class 2606 OID 33956)
-- Name: appear_to_surface_data app_to_surf_data_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.appear_to_surface_data
    ADD CONSTRAINT app_to_surf_data_fk1 FOREIGN KEY (appearance_id) REFERENCES citydb.appearance(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5607 (class 2606 OID 33961)
-- Name: appearance appearance_citymodel_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.appearance
    ADD CONSTRAINT appearance_citymodel_fk FOREIGN KEY (citymodel_id) REFERENCES citydb.citymodel(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5608 (class 2606 OID 33966)
-- Name: appearance appearance_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.appearance
    ADD CONSTRAINT appearance_cityobject_fk FOREIGN KEY (cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5686 (class 2606 OID 33971)
-- Name: building_furniture bldg_furn_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_furniture
    ADD CONSTRAINT bldg_furn_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5687 (class 2606 OID 33976)
-- Name: building_furniture bldg_furn_lod4brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_furniture
    ADD CONSTRAINT bldg_furn_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5688 (class 2606 OID 33981)
-- Name: building_furniture bldg_furn_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_furniture
    ADD CONSTRAINT bldg_furn_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5689 (class 2606 OID 33986)
-- Name: building_furniture bldg_furn_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_furniture
    ADD CONSTRAINT bldg_furn_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5690 (class 2606 OID 33991)
-- Name: building_furniture bldg_furn_room_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_furniture
    ADD CONSTRAINT bldg_furn_room_fk FOREIGN KEY (room_id) REFERENCES citydb.room(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5691 (class 2606 OID 33996)
-- Name: building_installation bldg_inst_building_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_building_fk FOREIGN KEY (building_id) REFERENCES citydb.building(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5692 (class 2606 OID 34001)
-- Name: building_installation bldg_inst_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5693 (class 2606 OID 34006)
-- Name: building_installation bldg_inst_lod2brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_lod2brep_fk FOREIGN KEY (lod2_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5694 (class 2606 OID 34011)
-- Name: building_installation bldg_inst_lod2impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_lod2impl_fk FOREIGN KEY (lod2_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5695 (class 2606 OID 34016)
-- Name: building_installation bldg_inst_lod3brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_lod3brep_fk FOREIGN KEY (lod3_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5696 (class 2606 OID 34021)
-- Name: building_installation bldg_inst_lod3impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5697 (class 2606 OID 34026)
-- Name: building_installation bldg_inst_lod4brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5698 (class 2606 OID 34031)
-- Name: building_installation bldg_inst_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5699 (class 2606 OID 34036)
-- Name: building_installation bldg_inst_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5700 (class 2606 OID 34041)
-- Name: building_installation bldg_inst_room_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_room_fk FOREIGN KEY (room_id) REFERENCES citydb.room(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5649 (class 2606 OID 34046)
-- Name: bridge_open_to_them_srf brd_open_to_them_srf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_open_to_them_srf
    ADD CONSTRAINT brd_open_to_them_srf_fk FOREIGN KEY (bridge_opening_id) REFERENCES citydb.bridge_opening(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5650 (class 2606 OID 34051)
-- Name: bridge_open_to_them_srf brd_open_to_them_srf_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_open_to_them_srf
    ADD CONSTRAINT brd_open_to_them_srf_fk1 FOREIGN KEY (bridge_thematic_surface_id) REFERENCES citydb.bridge_thematic_surface(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5663 (class 2606 OID 34056)
-- Name: bridge_thematic_surface brd_them_srf_brd_const_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_brd_const_fk FOREIGN KEY (bridge_constr_element_id) REFERENCES citydb.bridge_constr_element(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5664 (class 2606 OID 34061)
-- Name: bridge_thematic_surface brd_them_srf_brd_inst_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_brd_inst_fk FOREIGN KEY (bridge_installation_id) REFERENCES citydb.bridge_installation(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5665 (class 2606 OID 34066)
-- Name: bridge_thematic_surface brd_them_srf_brd_room_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_brd_room_fk FOREIGN KEY (bridge_room_id) REFERENCES citydb.bridge_room(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5666 (class 2606 OID 34071)
-- Name: bridge_thematic_surface brd_them_srf_bridge_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_bridge_fk FOREIGN KEY (bridge_id) REFERENCES citydb.bridge(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5667 (class 2606 OID 34076)
-- Name: bridge_thematic_surface brd_them_srf_cityobj_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_cityobj_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5668 (class 2606 OID 34081)
-- Name: bridge_thematic_surface brd_them_srf_lod2msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5669 (class 2606 OID 34086)
-- Name: bridge_thematic_surface brd_them_srf_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5670 (class 2606 OID 34091)
-- Name: bridge_thematic_surface brd_them_srf_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5671 (class 2606 OID 34096)
-- Name: bridge_thematic_surface brd_them_srf_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5609 (class 2606 OID 34101)
-- Name: breakline_relief breakline_rel_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.breakline_relief
    ADD CONSTRAINT breakline_rel_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5610 (class 2606 OID 34106)
-- Name: breakline_relief breakline_relief_comp_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.breakline_relief
    ADD CONSTRAINT breakline_relief_comp_fk FOREIGN KEY (id) REFERENCES citydb.relief_component(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5611 (class 2606 OID 34111)
-- Name: bridge bridge_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5623 (class 2606 OID 34116)
-- Name: bridge_constr_element bridge_constr_bridge_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_bridge_fk FOREIGN KEY (bridge_id) REFERENCES citydb.bridge(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5624 (class 2606 OID 34121)
-- Name: bridge_constr_element bridge_constr_cityobj_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_cityobj_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5625 (class 2606 OID 34126)
-- Name: bridge_constr_element bridge_constr_lod1brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod1brep_fk FOREIGN KEY (lod1_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5626 (class 2606 OID 34131)
-- Name: bridge_constr_element bridge_constr_lod1impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod1impl_fk FOREIGN KEY (lod1_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5627 (class 2606 OID 34136)
-- Name: bridge_constr_element bridge_constr_lod2brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod2brep_fk FOREIGN KEY (lod2_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5628 (class 2606 OID 34141)
-- Name: bridge_constr_element bridge_constr_lod2impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod2impl_fk FOREIGN KEY (lod2_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5629 (class 2606 OID 34146)
-- Name: bridge_constr_element bridge_constr_lod3brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod3brep_fk FOREIGN KEY (lod3_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5630 (class 2606 OID 34151)
-- Name: bridge_constr_element bridge_constr_lod3impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5631 (class 2606 OID 34156)
-- Name: bridge_constr_element bridge_constr_lod4brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5632 (class 2606 OID 34161)
-- Name: bridge_constr_element bridge_constr_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5633 (class 2606 OID 34166)
-- Name: bridge_constr_element bridge_constr_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5634 (class 2606 OID 34171)
-- Name: bridge_furniture bridge_furn_brd_room_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_furniture
    ADD CONSTRAINT bridge_furn_brd_room_fk FOREIGN KEY (bridge_room_id) REFERENCES citydb.bridge_room(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5635 (class 2606 OID 34176)
-- Name: bridge_furniture bridge_furn_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_furniture
    ADD CONSTRAINT bridge_furn_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5636 (class 2606 OID 34181)
-- Name: bridge_furniture bridge_furn_lod4brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_furniture
    ADD CONSTRAINT bridge_furn_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5637 (class 2606 OID 34186)
-- Name: bridge_furniture bridge_furn_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_furniture
    ADD CONSTRAINT bridge_furn_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5638 (class 2606 OID 34191)
-- Name: bridge_furniture bridge_furn_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_furniture
    ADD CONSTRAINT bridge_furn_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5639 (class 2606 OID 34196)
-- Name: bridge_installation bridge_inst_brd_room_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_brd_room_fk FOREIGN KEY (bridge_room_id) REFERENCES citydb.bridge_room(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5640 (class 2606 OID 34201)
-- Name: bridge_installation bridge_inst_bridge_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_bridge_fk FOREIGN KEY (bridge_id) REFERENCES citydb.bridge(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5641 (class 2606 OID 34206)
-- Name: bridge_installation bridge_inst_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5642 (class 2606 OID 34211)
-- Name: bridge_installation bridge_inst_lod2brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_lod2brep_fk FOREIGN KEY (lod2_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5643 (class 2606 OID 34216)
-- Name: bridge_installation bridge_inst_lod2impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_lod2impl_fk FOREIGN KEY (lod2_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5644 (class 2606 OID 34221)
-- Name: bridge_installation bridge_inst_lod3brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_lod3brep_fk FOREIGN KEY (lod3_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5645 (class 2606 OID 34226)
-- Name: bridge_installation bridge_inst_lod3impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5646 (class 2606 OID 34231)
-- Name: bridge_installation bridge_inst_lod4brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5647 (class 2606 OID 34236)
-- Name: bridge_installation bridge_inst_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5648 (class 2606 OID 34241)
-- Name: bridge_installation bridge_inst_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5612 (class 2606 OID 34246)
-- Name: bridge bridge_lod1msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod1msrf_fk FOREIGN KEY (lod1_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5613 (class 2606 OID 34251)
-- Name: bridge bridge_lod1solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod1solid_fk FOREIGN KEY (lod1_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5614 (class 2606 OID 34256)
-- Name: bridge bridge_lod2msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5615 (class 2606 OID 34261)
-- Name: bridge bridge_lod2solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod2solid_fk FOREIGN KEY (lod2_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5616 (class 2606 OID 34266)
-- Name: bridge bridge_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5617 (class 2606 OID 34271)
-- Name: bridge bridge_lod3solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod3solid_fk FOREIGN KEY (lod3_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5618 (class 2606 OID 34276)
-- Name: bridge bridge_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5619 (class 2606 OID 34281)
-- Name: bridge bridge_lod4solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod4solid_fk FOREIGN KEY (lod4_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5620 (class 2606 OID 34286)
-- Name: bridge bridge_objectclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_objectclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5651 (class 2606 OID 34291)
-- Name: bridge_opening bridge_open_address_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_open_address_fk FOREIGN KEY (address_id) REFERENCES citydb.address(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5652 (class 2606 OID 34296)
-- Name: bridge_opening bridge_open_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_open_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5653 (class 2606 OID 34301)
-- Name: bridge_opening bridge_open_lod3impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_open_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5654 (class 2606 OID 34306)
-- Name: bridge_opening bridge_open_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_open_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5655 (class 2606 OID 34311)
-- Name: bridge_opening bridge_open_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_open_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5656 (class 2606 OID 34316)
-- Name: bridge_opening bridge_open_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_open_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5657 (class 2606 OID 34321)
-- Name: bridge_opening bridge_open_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_open_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5621 (class 2606 OID 34326)
-- Name: bridge bridge_parent_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_parent_fk FOREIGN KEY (bridge_parent_id) REFERENCES citydb.bridge(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5658 (class 2606 OID 34331)
-- Name: bridge_room bridge_room_bridge_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_room
    ADD CONSTRAINT bridge_room_bridge_fk FOREIGN KEY (bridge_id) REFERENCES citydb.bridge(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5659 (class 2606 OID 34336)
-- Name: bridge_room bridge_room_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_room
    ADD CONSTRAINT bridge_room_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5660 (class 2606 OID 34341)
-- Name: bridge_room bridge_room_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_room
    ADD CONSTRAINT bridge_room_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5661 (class 2606 OID 34346)
-- Name: bridge_room bridge_room_lod4solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_room
    ADD CONSTRAINT bridge_room_lod4solid_fk FOREIGN KEY (lod4_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5662 (class 2606 OID 34351)
-- Name: bridge_room bridge_room_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge_room
    ADD CONSTRAINT bridge_room_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5622 (class 2606 OID 34356)
-- Name: bridge bridge_root_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_root_fk FOREIGN KEY (bridge_root_id) REFERENCES citydb.bridge(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5672 (class 2606 OID 34361)
-- Name: building building_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5673 (class 2606 OID 34366)
-- Name: building building_lod0footprint_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod0footprint_fk FOREIGN KEY (lod0_footprint_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5674 (class 2606 OID 34371)
-- Name: building building_lod0roofprint_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod0roofprint_fk FOREIGN KEY (lod0_roofprint_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5675 (class 2606 OID 34376)
-- Name: building building_lod1msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod1msrf_fk FOREIGN KEY (lod1_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5676 (class 2606 OID 34381)
-- Name: building building_lod1solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod1solid_fk FOREIGN KEY (lod1_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5677 (class 2606 OID 34386)
-- Name: building building_lod2msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5678 (class 2606 OID 34391)
-- Name: building building_lod2solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod2solid_fk FOREIGN KEY (lod2_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5679 (class 2606 OID 34396)
-- Name: building building_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5680 (class 2606 OID 34401)
-- Name: building building_lod3solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod3solid_fk FOREIGN KEY (lod3_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5681 (class 2606 OID 34406)
-- Name: building building_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5682 (class 2606 OID 34411)
-- Name: building building_lod4solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod4solid_fk FOREIGN KEY (lod4_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5683 (class 2606 OID 34416)
-- Name: building building_objectclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_objectclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5684 (class 2606 OID 34421)
-- Name: building building_parent_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_parent_fk FOREIGN KEY (building_parent_id) REFERENCES citydb.building(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5685 (class 2606 OID 34426)
-- Name: building building_root_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_root_fk FOREIGN KEY (building_root_id) REFERENCES citydb.building(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5701 (class 2606 OID 34431)
-- Name: city_furniture city_furn_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5702 (class 2606 OID 34436)
-- Name: city_furniture city_furn_lod1brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod1brep_fk FOREIGN KEY (lod1_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5703 (class 2606 OID 34441)
-- Name: city_furniture city_furn_lod1impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod1impl_fk FOREIGN KEY (lod1_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5704 (class 2606 OID 34446)
-- Name: city_furniture city_furn_lod2brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod2brep_fk FOREIGN KEY (lod2_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5705 (class 2606 OID 34451)
-- Name: city_furniture city_furn_lod2impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod2impl_fk FOREIGN KEY (lod2_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5706 (class 2606 OID 34456)
-- Name: city_furniture city_furn_lod3brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod3brep_fk FOREIGN KEY (lod3_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5707 (class 2606 OID 34461)
-- Name: city_furniture city_furn_lod3impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5708 (class 2606 OID 34466)
-- Name: city_furniture city_furn_lod4brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5709 (class 2606 OID 34471)
-- Name: city_furniture city_furn_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5710 (class 2606 OID 34476)
-- Name: city_furniture city_furn_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5716 (class 2606 OID 34481)
-- Name: cityobject_member cityobject_member_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobject_member
    ADD CONSTRAINT cityobject_member_fk FOREIGN KEY (cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5717 (class 2606 OID 34486)
-- Name: cityobject_member cityobject_member_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobject_member
    ADD CONSTRAINT cityobject_member_fk1 FOREIGN KEY (citymodel_id) REFERENCES citydb.citymodel(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5711 (class 2606 OID 34491)
-- Name: cityobject cityobject_objectclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobject
    ADD CONSTRAINT cityobject_objectclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5722 (class 2606 OID 34496)
-- Name: external_reference ext_ref_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.external_reference
    ADD CONSTRAINT ext_ref_cityobject_fk FOREIGN KEY (cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5725 (class 2606 OID 34501)
-- Name: generic_cityobject gen_object_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5726 (class 2606 OID 34506)
-- Name: generic_cityobject gen_object_lod0brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod0brep_fk FOREIGN KEY (lod0_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5727 (class 2606 OID 34511)
-- Name: generic_cityobject gen_object_lod0impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod0impl_fk FOREIGN KEY (lod0_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5728 (class 2606 OID 34516)
-- Name: generic_cityobject gen_object_lod1brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod1brep_fk FOREIGN KEY (lod1_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5729 (class 2606 OID 34521)
-- Name: generic_cityobject gen_object_lod1impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod1impl_fk FOREIGN KEY (lod1_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5730 (class 2606 OID 34526)
-- Name: generic_cityobject gen_object_lod2brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod2brep_fk FOREIGN KEY (lod2_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5731 (class 2606 OID 34531)
-- Name: generic_cityobject gen_object_lod2impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod2impl_fk FOREIGN KEY (lod2_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5732 (class 2606 OID 34536)
-- Name: generic_cityobject gen_object_lod3brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod3brep_fk FOREIGN KEY (lod3_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5733 (class 2606 OID 34541)
-- Name: generic_cityobject gen_object_lod3impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5734 (class 2606 OID 34546)
-- Name: generic_cityobject gen_object_lod4brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5735 (class 2606 OID 34551)
-- Name: generic_cityobject gen_object_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5736 (class 2606 OID 34556)
-- Name: generic_cityobject gen_object_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5723 (class 2606 OID 34561)
-- Name: generalization general_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generalization
    ADD CONSTRAINT general_cityobject_fk FOREIGN KEY (cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5724 (class 2606 OID 34566)
-- Name: generalization general_generalizes_to_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.generalization
    ADD CONSTRAINT general_generalizes_to_fk FOREIGN KEY (generalizes_to_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5712 (class 2606 OID 34571)
-- Name: cityobject_genericattrib genericattrib_cityobj_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobject_genericattrib
    ADD CONSTRAINT genericattrib_cityobj_fk FOREIGN KEY (cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5713 (class 2606 OID 34576)
-- Name: cityobject_genericattrib genericattrib_geom_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobject_genericattrib
    ADD CONSTRAINT genericattrib_geom_fk FOREIGN KEY (surface_geometry_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5714 (class 2606 OID 34581)
-- Name: cityobject_genericattrib genericattrib_parent_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobject_genericattrib
    ADD CONSTRAINT genericattrib_parent_fk FOREIGN KEY (parent_genattrib_id) REFERENCES citydb.cityobject_genericattrib(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5715 (class 2606 OID 34586)
-- Name: cityobject_genericattrib genericattrib_root_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobject_genericattrib
    ADD CONSTRAINT genericattrib_root_fk FOREIGN KEY (root_genattrib_id) REFERENCES citydb.cityobject_genericattrib(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5718 (class 2606 OID 34591)
-- Name: cityobjectgroup group_brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobjectgroup
    ADD CONSTRAINT group_brep_fk FOREIGN KEY (brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5719 (class 2606 OID 34596)
-- Name: cityobjectgroup group_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobjectgroup
    ADD CONSTRAINT group_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5720 (class 2606 OID 34601)
-- Name: cityobjectgroup group_objectclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobjectgroup
    ADD CONSTRAINT group_objectclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5721 (class 2606 OID 34606)
-- Name: cityobjectgroup group_parent_cityobj_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.cityobjectgroup
    ADD CONSTRAINT group_parent_cityobj_fk FOREIGN KEY (parent_cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5737 (class 2606 OID 34611)
-- Name: group_to_cityobject group_to_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.group_to_cityobject
    ADD CONSTRAINT group_to_cityobject_fk FOREIGN KEY (cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5738 (class 2606 OID 34616)
-- Name: group_to_cityobject group_to_cityobject_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.group_to_cityobject
    ADD CONSTRAINT group_to_cityobject_fk1 FOREIGN KEY (cityobjectgroup_id) REFERENCES citydb.cityobjectgroup(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5739 (class 2606 OID 34621)
-- Name: implicit_geometry implicit_geom_brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.implicit_geometry
    ADD CONSTRAINT implicit_geom_brep_fk FOREIGN KEY (relative_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5740 (class 2606 OID 34626)
-- Name: land_use land_use_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5741 (class 2606 OID 34631)
-- Name: land_use land_use_lod0msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_lod0msrf_fk FOREIGN KEY (lod0_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5742 (class 2606 OID 34636)
-- Name: land_use land_use_lod1msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_lod1msrf_fk FOREIGN KEY (lod1_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5743 (class 2606 OID 34641)
-- Name: land_use land_use_lod2msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5744 (class 2606 OID 34646)
-- Name: land_use land_use_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5745 (class 2606 OID 34651)
-- Name: land_use land_use_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5746 (class 2606 OID 34656)
-- Name: land_use land_use_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5747 (class 2606 OID 34661)
-- Name: masspoint_relief masspoint_rel_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.masspoint_relief
    ADD CONSTRAINT masspoint_rel_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5748 (class 2606 OID 34666)
-- Name: masspoint_relief masspoint_relief_comp_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.masspoint_relief
    ADD CONSTRAINT masspoint_relief_comp_fk FOREIGN KEY (id) REFERENCES citydb.relief_component(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5749 (class 2606 OID 34671)
-- Name: objectclass objectclass_ade_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.objectclass
    ADD CONSTRAINT objectclass_ade_fk FOREIGN KEY (ade_id) REFERENCES citydb.ade(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5750 (class 2606 OID 34676)
-- Name: objectclass objectclass_baseclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.objectclass
    ADD CONSTRAINT objectclass_baseclass_fk FOREIGN KEY (baseclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5751 (class 2606 OID 34681)
-- Name: objectclass objectclass_superclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.objectclass
    ADD CONSTRAINT objectclass_superclass_fk FOREIGN KEY (superclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5759 (class 2606 OID 34686)
-- Name: opening_to_them_surface open_to_them_surface_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.opening_to_them_surface
    ADD CONSTRAINT open_to_them_surface_fk FOREIGN KEY (opening_id) REFERENCES citydb.opening(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5760 (class 2606 OID 34691)
-- Name: opening_to_them_surface open_to_them_surface_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.opening_to_them_surface
    ADD CONSTRAINT open_to_them_surface_fk1 FOREIGN KEY (thematic_surface_id) REFERENCES citydb.thematic_surface(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5752 (class 2606 OID 34696)
-- Name: opening opening_address_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_address_fk FOREIGN KEY (address_id) REFERENCES citydb.address(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5753 (class 2606 OID 34701)
-- Name: opening opening_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5754 (class 2606 OID 34706)
-- Name: opening opening_lod3impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5755 (class 2606 OID 34711)
-- Name: opening opening_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5756 (class 2606 OID 34716)
-- Name: opening opening_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5757 (class 2606 OID 34721)
-- Name: opening opening_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5758 (class 2606 OID 34726)
-- Name: opening opening_objectclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_objectclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5761 (class 2606 OID 34731)
-- Name: plant_cover plant_cover_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5762 (class 2606 OID 34736)
-- Name: plant_cover plant_cover_lod1msolid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod1msolid_fk FOREIGN KEY (lod1_multi_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5763 (class 2606 OID 34741)
-- Name: plant_cover plant_cover_lod1msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod1msrf_fk FOREIGN KEY (lod1_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5764 (class 2606 OID 34746)
-- Name: plant_cover plant_cover_lod2msolid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod2msolid_fk FOREIGN KEY (lod2_multi_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5765 (class 2606 OID 34751)
-- Name: plant_cover plant_cover_lod2msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5766 (class 2606 OID 34756)
-- Name: plant_cover plant_cover_lod3msolid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod3msolid_fk FOREIGN KEY (lod3_multi_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5767 (class 2606 OID 34761)
-- Name: plant_cover plant_cover_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5768 (class 2606 OID 34766)
-- Name: plant_cover plant_cover_lod4msolid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod4msolid_fk FOREIGN KEY (lod4_multi_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5769 (class 2606 OID 34771)
-- Name: plant_cover plant_cover_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5770 (class 2606 OID 34776)
-- Name: plant_cover plant_cover_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5771 (class 2606 OID 34781)
-- Name: raster_relief raster_relief_comp_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.raster_relief
    ADD CONSTRAINT raster_relief_comp_fk FOREIGN KEY (id) REFERENCES citydb.relief_component(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5772 (class 2606 OID 34786)
-- Name: raster_relief raster_relief_coverage_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.raster_relief
    ADD CONSTRAINT raster_relief_coverage_fk FOREIGN KEY (coverage_id) REFERENCES citydb.grid_coverage(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5773 (class 2606 OID 34791)
-- Name: raster_relief raster_relief_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.raster_relief
    ADD CONSTRAINT raster_relief_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5776 (class 2606 OID 34796)
-- Name: relief_feat_to_rel_comp rel_feat_to_rel_comp_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.relief_feat_to_rel_comp
    ADD CONSTRAINT rel_feat_to_rel_comp_fk FOREIGN KEY (relief_component_id) REFERENCES citydb.relief_component(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5777 (class 2606 OID 34801)
-- Name: relief_feat_to_rel_comp rel_feat_to_rel_comp_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.relief_feat_to_rel_comp
    ADD CONSTRAINT rel_feat_to_rel_comp_fk1 FOREIGN KEY (relief_feature_id) REFERENCES citydb.relief_feature(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5774 (class 2606 OID 34806)
-- Name: relief_component relief_comp_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.relief_component
    ADD CONSTRAINT relief_comp_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5775 (class 2606 OID 34811)
-- Name: relief_component relief_comp_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.relief_component
    ADD CONSTRAINT relief_comp_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5778 (class 2606 OID 34816)
-- Name: relief_feature relief_feat_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.relief_feature
    ADD CONSTRAINT relief_feat_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5779 (class 2606 OID 34821)
-- Name: relief_feature relief_feat_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.relief_feature
    ADD CONSTRAINT relief_feat_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5780 (class 2606 OID 34826)
-- Name: room room_building_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.room
    ADD CONSTRAINT room_building_fk FOREIGN KEY (building_id) REFERENCES citydb.building(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5781 (class 2606 OID 34831)
-- Name: room room_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.room
    ADD CONSTRAINT room_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5782 (class 2606 OID 34836)
-- Name: room room_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.room
    ADD CONSTRAINT room_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5783 (class 2606 OID 34841)
-- Name: room room_lod4solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.room
    ADD CONSTRAINT room_lod4solid_fk FOREIGN KEY (lod4_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5784 (class 2606 OID 34846)
-- Name: room room_objectclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.room
    ADD CONSTRAINT room_objectclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5785 (class 2606 OID 34851)
-- Name: schema schema_ade_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.schema
    ADD CONSTRAINT schema_ade_fk FOREIGN KEY (ade_id) REFERENCES citydb.ade(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5786 (class 2606 OID 34856)
-- Name: schema_referencing schema_referencing_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.schema_referencing
    ADD CONSTRAINT schema_referencing_fk1 FOREIGN KEY (referencing_id) REFERENCES citydb.schema(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5787 (class 2606 OID 34861)
-- Name: schema_referencing schema_referencing_fk2; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.schema_referencing
    ADD CONSTRAINT schema_referencing_fk2 FOREIGN KEY (referenced_id) REFERENCES citydb.schema(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5788 (class 2606 OID 34866)
-- Name: schema_to_objectclass schema_to_objectclass_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.schema_to_objectclass
    ADD CONSTRAINT schema_to_objectclass_fk1 FOREIGN KEY (schema_id) REFERENCES citydb.schema(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5789 (class 2606 OID 34871)
-- Name: schema_to_objectclass schema_to_objectclass_fk2; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.schema_to_objectclass
    ADD CONSTRAINT schema_to_objectclass_fk2 FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5790 (class 2606 OID 34876)
-- Name: solitary_vegetat_object sol_veg_obj_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5791 (class 2606 OID 34881)
-- Name: solitary_vegetat_object sol_veg_obj_lod1brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod1brep_fk FOREIGN KEY (lod1_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5792 (class 2606 OID 34886)
-- Name: solitary_vegetat_object sol_veg_obj_lod1impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod1impl_fk FOREIGN KEY (lod1_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5793 (class 2606 OID 34891)
-- Name: solitary_vegetat_object sol_veg_obj_lod2brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod2brep_fk FOREIGN KEY (lod2_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5794 (class 2606 OID 34896)
-- Name: solitary_vegetat_object sol_veg_obj_lod2impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod2impl_fk FOREIGN KEY (lod2_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5795 (class 2606 OID 34901)
-- Name: solitary_vegetat_object sol_veg_obj_lod3brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod3brep_fk FOREIGN KEY (lod3_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5796 (class 2606 OID 34906)
-- Name: solitary_vegetat_object sol_veg_obj_lod3impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5797 (class 2606 OID 34911)
-- Name: solitary_vegetat_object sol_veg_obj_lod4brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5798 (class 2606 OID 34916)
-- Name: solitary_vegetat_object sol_veg_obj_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5799 (class 2606 OID 34921)
-- Name: solitary_vegetat_object sol_veg_obj_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5800 (class 2606 OID 34926)
-- Name: surface_data surface_data_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.surface_data
    ADD CONSTRAINT surface_data_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5801 (class 2606 OID 34931)
-- Name: surface_data surface_data_tex_image_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.surface_data
    ADD CONSTRAINT surface_data_tex_image_fk FOREIGN KEY (tex_image_id) REFERENCES citydb.tex_image(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5802 (class 2606 OID 34936)
-- Name: surface_geometry surface_geom_cityobj_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.surface_geometry
    ADD CONSTRAINT surface_geom_cityobj_fk FOREIGN KEY (cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5803 (class 2606 OID 34941)
-- Name: surface_geometry surface_geom_parent_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.surface_geometry
    ADD CONSTRAINT surface_geom_parent_fk FOREIGN KEY (parent_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5804 (class 2606 OID 34946)
-- Name: surface_geometry surface_geom_root_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.surface_geometry
    ADD CONSTRAINT surface_geom_root_fk FOREIGN KEY (root_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5805 (class 2606 OID 34951)
-- Name: textureparam texparam_geom_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.textureparam
    ADD CONSTRAINT texparam_geom_fk FOREIGN KEY (surface_geometry_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5806 (class 2606 OID 34956)
-- Name: textureparam texparam_surface_data_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.textureparam
    ADD CONSTRAINT texparam_surface_data_fk FOREIGN KEY (surface_data_id) REFERENCES citydb.surface_data(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5807 (class 2606 OID 34961)
-- Name: thematic_surface them_surface_bldg_inst_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_bldg_inst_fk FOREIGN KEY (building_installation_id) REFERENCES citydb.building_installation(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5808 (class 2606 OID 34966)
-- Name: thematic_surface them_surface_building_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_building_fk FOREIGN KEY (building_id) REFERENCES citydb.building(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5809 (class 2606 OID 34971)
-- Name: thematic_surface them_surface_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5810 (class 2606 OID 34976)
-- Name: thematic_surface them_surface_lod2msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5811 (class 2606 OID 34981)
-- Name: thematic_surface them_surface_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5812 (class 2606 OID 34986)
-- Name: thematic_surface them_surface_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5813 (class 2606 OID 34991)
-- Name: thematic_surface them_surface_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5814 (class 2606 OID 34996)
-- Name: thematic_surface them_surface_room_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_room_fk FOREIGN KEY (room_id) REFERENCES citydb.room(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5815 (class 2606 OID 35001)
-- Name: tin_relief tin_relief_comp_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tin_relief
    ADD CONSTRAINT tin_relief_comp_fk FOREIGN KEY (id) REFERENCES citydb.relief_component(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5816 (class 2606 OID 35006)
-- Name: tin_relief tin_relief_geom_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tin_relief
    ADD CONSTRAINT tin_relief_geom_fk FOREIGN KEY (surface_geometry_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5817 (class 2606 OID 35011)
-- Name: tin_relief tin_relief_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tin_relief
    ADD CONSTRAINT tin_relief_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5818 (class 2606 OID 35016)
-- Name: traffic_area traffic_area_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.traffic_area
    ADD CONSTRAINT traffic_area_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5819 (class 2606 OID 35021)
-- Name: traffic_area traffic_area_lod2msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.traffic_area
    ADD CONSTRAINT traffic_area_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5820 (class 2606 OID 35026)
-- Name: traffic_area traffic_area_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.traffic_area
    ADD CONSTRAINT traffic_area_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5821 (class 2606 OID 35031)
-- Name: traffic_area traffic_area_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.traffic_area
    ADD CONSTRAINT traffic_area_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5822 (class 2606 OID 35036)
-- Name: traffic_area traffic_area_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.traffic_area
    ADD CONSTRAINT traffic_area_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5823 (class 2606 OID 35041)
-- Name: traffic_area traffic_area_trancmplx_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.traffic_area
    ADD CONSTRAINT traffic_area_trancmplx_fk FOREIGN KEY (transportation_complex_id) REFERENCES citydb.transportation_complex(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5824 (class 2606 OID 35046)
-- Name: transportation_complex tran_complex_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.transportation_complex
    ADD CONSTRAINT tran_complex_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5825 (class 2606 OID 35051)
-- Name: transportation_complex tran_complex_lod1msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.transportation_complex
    ADD CONSTRAINT tran_complex_lod1msrf_fk FOREIGN KEY (lod1_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5826 (class 2606 OID 35056)
-- Name: transportation_complex tran_complex_lod2msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.transportation_complex
    ADD CONSTRAINT tran_complex_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5827 (class 2606 OID 35061)
-- Name: transportation_complex tran_complex_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.transportation_complex
    ADD CONSTRAINT tran_complex_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5828 (class 2606 OID 35066)
-- Name: transportation_complex tran_complex_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.transportation_complex
    ADD CONSTRAINT tran_complex_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5829 (class 2606 OID 35071)
-- Name: transportation_complex tran_complex_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.transportation_complex
    ADD CONSTRAINT tran_complex_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5847 (class 2606 OID 35076)
-- Name: tunnel_hollow_space tun_hspace_cityobj_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_hollow_space
    ADD CONSTRAINT tun_hspace_cityobj_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5848 (class 2606 OID 35081)
-- Name: tunnel_hollow_space tun_hspace_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_hollow_space
    ADD CONSTRAINT tun_hspace_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5849 (class 2606 OID 35086)
-- Name: tunnel_hollow_space tun_hspace_lod4solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_hollow_space
    ADD CONSTRAINT tun_hspace_lod4solid_fk FOREIGN KEY (lod4_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5850 (class 2606 OID 35091)
-- Name: tunnel_hollow_space tun_hspace_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_hollow_space
    ADD CONSTRAINT tun_hspace_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5851 (class 2606 OID 35096)
-- Name: tunnel_hollow_space tun_hspace_tunnel_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_hollow_space
    ADD CONSTRAINT tun_hspace_tunnel_fk FOREIGN KEY (tunnel_id) REFERENCES citydb.tunnel(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5862 (class 2606 OID 35101)
-- Name: tunnel_open_to_them_srf tun_open_to_them_srf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_open_to_them_srf
    ADD CONSTRAINT tun_open_to_them_srf_fk FOREIGN KEY (tunnel_opening_id) REFERENCES citydb.tunnel_opening(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5863 (class 2606 OID 35106)
-- Name: tunnel_open_to_them_srf tun_open_to_them_srf_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_open_to_them_srf
    ADD CONSTRAINT tun_open_to_them_srf_fk1 FOREIGN KEY (tunnel_thematic_surface_id) REFERENCES citydb.tunnel_thematic_surface(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5870 (class 2606 OID 35111)
-- Name: tunnel_thematic_surface tun_them_srf_cityobj_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_cityobj_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5871 (class 2606 OID 35116)
-- Name: tunnel_thematic_surface tun_them_srf_hspace_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_hspace_fk FOREIGN KEY (tunnel_hollow_space_id) REFERENCES citydb.tunnel_hollow_space(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5872 (class 2606 OID 35121)
-- Name: tunnel_thematic_surface tun_them_srf_lod2msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5873 (class 2606 OID 35126)
-- Name: tunnel_thematic_surface tun_them_srf_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5874 (class 2606 OID 35131)
-- Name: tunnel_thematic_surface tun_them_srf_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5875 (class 2606 OID 35136)
-- Name: tunnel_thematic_surface tun_them_srf_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5876 (class 2606 OID 35141)
-- Name: tunnel_thematic_surface tun_them_srf_tun_inst_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_tun_inst_fk FOREIGN KEY (tunnel_installation_id) REFERENCES citydb.tunnel_installation(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5877 (class 2606 OID 35146)
-- Name: tunnel_thematic_surface tun_them_srf_tunnel_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_tunnel_fk FOREIGN KEY (tunnel_id) REFERENCES citydb.tunnel(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5830 (class 2606 OID 35151)
-- Name: tunnel tunnel_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5842 (class 2606 OID 35156)
-- Name: tunnel_furniture tunnel_furn_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_furniture
    ADD CONSTRAINT tunnel_furn_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5843 (class 2606 OID 35161)
-- Name: tunnel_furniture tunnel_furn_hspace_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_furniture
    ADD CONSTRAINT tunnel_furn_hspace_fk FOREIGN KEY (tunnel_hollow_space_id) REFERENCES citydb.tunnel_hollow_space(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5844 (class 2606 OID 35166)
-- Name: tunnel_furniture tunnel_furn_lod4brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_furniture
    ADD CONSTRAINT tunnel_furn_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5845 (class 2606 OID 35171)
-- Name: tunnel_furniture tunnel_furn_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_furniture
    ADD CONSTRAINT tunnel_furn_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5846 (class 2606 OID 35176)
-- Name: tunnel_furniture tunnel_furn_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_furniture
    ADD CONSTRAINT tunnel_furn_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5852 (class 2606 OID 35181)
-- Name: tunnel_installation tunnel_inst_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5853 (class 2606 OID 35186)
-- Name: tunnel_installation tunnel_inst_hspace_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_hspace_fk FOREIGN KEY (tunnel_hollow_space_id) REFERENCES citydb.tunnel_hollow_space(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5854 (class 2606 OID 35191)
-- Name: tunnel_installation tunnel_inst_lod2brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_lod2brep_fk FOREIGN KEY (lod2_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5855 (class 2606 OID 35196)
-- Name: tunnel_installation tunnel_inst_lod2impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_lod2impl_fk FOREIGN KEY (lod2_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5856 (class 2606 OID 35201)
-- Name: tunnel_installation tunnel_inst_lod3brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_lod3brep_fk FOREIGN KEY (lod3_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5857 (class 2606 OID 35206)
-- Name: tunnel_installation tunnel_inst_lod3impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5858 (class 2606 OID 35211)
-- Name: tunnel_installation tunnel_inst_lod4brep_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5859 (class 2606 OID 35216)
-- Name: tunnel_installation tunnel_inst_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5860 (class 2606 OID 35221)
-- Name: tunnel_installation tunnel_inst_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5861 (class 2606 OID 35226)
-- Name: tunnel_installation tunnel_inst_tunnel_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_tunnel_fk FOREIGN KEY (tunnel_id) REFERENCES citydb.tunnel(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5831 (class 2606 OID 35231)
-- Name: tunnel tunnel_lod1msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod1msrf_fk FOREIGN KEY (lod1_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5832 (class 2606 OID 35236)
-- Name: tunnel tunnel_lod1solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod1solid_fk FOREIGN KEY (lod1_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5833 (class 2606 OID 35241)
-- Name: tunnel tunnel_lod2msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5834 (class 2606 OID 35246)
-- Name: tunnel tunnel_lod2solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod2solid_fk FOREIGN KEY (lod2_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5835 (class 2606 OID 35251)
-- Name: tunnel tunnel_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5836 (class 2606 OID 35256)
-- Name: tunnel tunnel_lod3solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod3solid_fk FOREIGN KEY (lod3_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5837 (class 2606 OID 35261)
-- Name: tunnel tunnel_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5838 (class 2606 OID 35266)
-- Name: tunnel tunnel_lod4solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod4solid_fk FOREIGN KEY (lod4_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5839 (class 2606 OID 35271)
-- Name: tunnel tunnel_objectclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_objectclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5864 (class 2606 OID 35276)
-- Name: tunnel_opening tunnel_open_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_opening
    ADD CONSTRAINT tunnel_open_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5865 (class 2606 OID 35281)
-- Name: tunnel_opening tunnel_open_lod3impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_opening
    ADD CONSTRAINT tunnel_open_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5866 (class 2606 OID 35286)
-- Name: tunnel_opening tunnel_open_lod3msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_opening
    ADD CONSTRAINT tunnel_open_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5867 (class 2606 OID 35291)
-- Name: tunnel_opening tunnel_open_lod4impl_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_opening
    ADD CONSTRAINT tunnel_open_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5868 (class 2606 OID 35296)
-- Name: tunnel_opening tunnel_open_lod4msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_opening
    ADD CONSTRAINT tunnel_open_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5869 (class 2606 OID 35301)
-- Name: tunnel_opening tunnel_open_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel_opening
    ADD CONSTRAINT tunnel_open_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5840 (class 2606 OID 35306)
-- Name: tunnel tunnel_parent_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_parent_fk FOREIGN KEY (tunnel_parent_id) REFERENCES citydb.tunnel(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5841 (class 2606 OID 35311)
-- Name: tunnel tunnel_root_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_root_fk FOREIGN KEY (tunnel_root_id) REFERENCES citydb.tunnel(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5888 (class 2606 OID 35316)
-- Name: waterboundary_surface waterbnd_srf_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterboundary_surface
    ADD CONSTRAINT waterbnd_srf_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5889 (class 2606 OID 35321)
-- Name: waterboundary_surface waterbnd_srf_lod2srf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterboundary_surface
    ADD CONSTRAINT waterbnd_srf_lod2srf_fk FOREIGN KEY (lod2_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5890 (class 2606 OID 35326)
-- Name: waterboundary_surface waterbnd_srf_lod3srf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterboundary_surface
    ADD CONSTRAINT waterbnd_srf_lod3srf_fk FOREIGN KEY (lod3_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5891 (class 2606 OID 35331)
-- Name: waterboundary_surface waterbnd_srf_lod4srf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterboundary_surface
    ADD CONSTRAINT waterbnd_srf_lod4srf_fk FOREIGN KEY (lod4_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5892 (class 2606 OID 35336)
-- Name: waterboundary_surface waterbnd_srf_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterboundary_surface
    ADD CONSTRAINT waterbnd_srf_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5878 (class 2606 OID 35341)
-- Name: waterbod_to_waterbnd_srf waterbod_to_waterbnd_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbod_to_waterbnd_srf
    ADD CONSTRAINT waterbod_to_waterbnd_fk FOREIGN KEY (waterboundary_surface_id) REFERENCES citydb.waterboundary_surface(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 5879 (class 2606 OID 35346)
-- Name: waterbod_to_waterbnd_srf waterbod_to_waterbnd_fk1; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbod_to_waterbnd_srf
    ADD CONSTRAINT waterbod_to_waterbnd_fk1 FOREIGN KEY (waterbody_id) REFERENCES citydb.waterbody(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5880 (class 2606 OID 35351)
-- Name: waterbody waterbody_cityobject_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5881 (class 2606 OID 35356)
-- Name: waterbody waterbody_lod0msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_lod0msrf_fk FOREIGN KEY (lod0_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5882 (class 2606 OID 35361)
-- Name: waterbody waterbody_lod1msrf_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_lod1msrf_fk FOREIGN KEY (lod1_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5883 (class 2606 OID 35366)
-- Name: waterbody waterbody_lod1solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_lod1solid_fk FOREIGN KEY (lod1_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5884 (class 2606 OID 35371)
-- Name: waterbody waterbody_lod2solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_lod2solid_fk FOREIGN KEY (lod2_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5885 (class 2606 OID 35376)
-- Name: waterbody waterbody_lod3solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_lod3solid_fk FOREIGN KEY (lod3_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5886 (class 2606 OID 35381)
-- Name: waterbody waterbody_lod4solid_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_lod4solid_fk FOREIGN KEY (lod4_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;


--
-- TOC entry 5887 (class 2606 OID 35386)
-- Name: waterbody waterbody_objclass_fk; Type: FK CONSTRAINT; Schema: citydb; Owner: postgres
--

ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;


-- Completed on 2022-03-24 16:28:01

--
-- PostgreSQL database dump complete
--


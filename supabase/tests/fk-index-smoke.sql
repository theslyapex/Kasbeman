DO $test$
DECLARE
  v_missing text;
BEGIN
  SELECT string_agg(e.index_name, ', ' ORDER BY e.index_name)
  INTO v_missing
  FROM (VALUES
    ('business_invitations_invited_by_idx', 'business_invitations', ARRAY['invited_by']::text[]),
    ('businesses_created_by_idx', 'businesses', ARRAY['created_by']::text[]),
    ('member_role_assignments_assigned_by_idx', 'member_role_assignments', ARRAY['assigned_by']::text[]),
    ('member_role_assignments_branch_fk_idx', 'member_role_assignments', ARRAY['business_id','branch_id']::text[]),
    ('member_role_assignments_role_fk_idx', 'member_role_assignments', ARRAY['business_id','role_id']::text[]),
    ('roles_created_by_idx', 'roles', ARRAY['created_by']::text[])
  ) AS e(index_name, table_name, expected_columns)
  WHERE NOT EXISTS (
    SELECT 1
    FROM pg_class idx
    JOIN pg_index ix ON ix.indexrelid = idx.oid
    JOIN pg_class tbl ON tbl.oid = ix.indrelid
    CROSS JOIN LATERAL (
      SELECT array_agg(a.attname::text ORDER BY k.ord) AS columns
      FROM unnest(ix.indkey) WITH ORDINALITY AS k(attnum, ord)
      JOIN pg_attribute a
        ON a.attrelid = tbl.oid
       AND a.attnum = k.attnum
      WHERE k.ord <= ix.indnkeyatts
    ) actual
    WHERE idx.relname = e.index_name
      AND tbl.relname = e.table_name
      AND ix.indisvalid
      AND actual.columns = e.expected_columns
  );

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'Missing or malformed FK indexes: %', v_missing;
  END IF;
END;
$test$;

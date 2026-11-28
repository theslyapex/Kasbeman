\set ON_ERROR_STOP on

-- Invitation tokens are delivered once by the create RPC; the stored hash is
-- not selectable by API roles and invitation rows are not directly writable.
RESET ROLE;
UPDATE auth.users
SET email = 'invitee@kasbeman.test', email_confirmed_at = now()
WHERE id = '10000000-0000-4000-8000-000000000005';
UPDATE auth.users
SET email = 'other@kasbeman.test', email_confirmed_at = now()
WHERE id = '10000000-0000-4000-8000-000000000006';

-- Custom role definitions and permission grants are tenant-scoped and guarded by RBAC.
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

INSERT INTO public.roles (
  business_id, role_key, name, description, is_system, created_by
) VALUES (
  :'business_id'::uuid, 'custom_sales_ops', 'کارشناس فروش',
  'دسترسی محدود عملیات فروش', false, auth.uid()
) RETURNING id AS custom_role_id \gset
SELECT set_config('kasbeman.test_custom_role_id', :'custom_role_id', false);

INSERT INTO public.role_permissions (business_id, role_id, permission_key)
VALUES
  (:'business_id'::uuid, :'custom_role_id'::uuid, 'dashboard.read'),
  (:'business_id'::uuid, :'custom_role_id'::uuid, 'sales.orders.read');

DO $custom_role_test$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.roles
    WHERE id = current_setting('kasbeman.test_custom_role_id')::uuid
      AND business_id = current_setting('kasbeman.test_business_id')::uuid
      AND is_system = false
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Authorized owner could not create a custom role';
  END IF;
  IF (
    SELECT count(*) FROM public.role_permissions
    WHERE role_id = current_setting('kasbeman.test_custom_role_id')::uuid
  ) <> 2 THEN
    RAISE EXCEPTION 'Custom role permission grants were not persisted';
  END IF;

  UPDATE public.roles SET name = 'کارشناس فروش ارشد'
  WHERE id = current_setting('kasbeman.test_custom_role_id')::uuid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Authorized owner could not update a custom role';
  END IF;

  UPDATE public.roles SET name = 'مالک جعلی'
  WHERE business_id = current_setting('kasbeman.test_business_id')::uuid
    AND role_key = 'owner';
  IF FOUND THEN
    RAISE EXCEPTION 'System owner role was modified';
  END IF;
END
$custom_role_test$;

-- A regular member cannot create roles or edit permission grants.
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';

DO $custom_role_test$
BEGIN
  BEGIN
    INSERT INTO public.roles (
      business_id, role_key, name, is_system, created_by
    ) VALUES (
      current_setting('kasbeman.test_business_id')::uuid,
      'forged_role', 'نقش جعلی', false, auth.uid()
    );
    RAISE EXCEPTION 'Member without team.roles.manage created a custom role';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$custom_role_test$;

SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

SELECT invitation_id AS invite_id, invitation_token AS invite_token
FROM public.create_business_invitation(
  :'business_id'::uuid, 'invitee@kasbeman.test', 'member'
) \gset
SELECT set_config('kasbeman.test_invite_id', :'invite_id', false);
SELECT set_config('kasbeman.test_invite_token', :'invite_token', false);

DO $$
BEGIN
  IF has_column_privilege(
    'authenticated', 'public.business_invitations', 'token_hash', 'SELECT'
  ) THEN
    RAISE EXCEPTION 'Authenticated role can read invitation token hashes';
  END IF;
  IF has_column_privilege(
    'authenticated', 'public.business_invitations', 'status', 'UPDATE'
  ) OR has_column_privilege(
    'authenticated', 'public.business_invitations', 'email', 'UPDATE'
  ) THEN
    RAISE EXCEPTION 'Authenticated role can directly mutate invitation state';
  END IF;

  IF has_column_privilege(
    'authenticated', 'public.member_role_assignments', 'role_id', 'UPDATE'
  ) THEN
    RAISE EXCEPTION 'Authenticated role can directly rewrite role assignments';
  END IF;

  BEGIN
    INSERT INTO public.business_invitations (
      business_id, email, role_key, status, invited_by, token_hash, expires_at
    ) VALUES (
      current_setting('kasbeman.test_business_id')::uuid,
      'forged@kasbeman.test', 'member', 'pending',
      auth.uid(), repeat('a', 64), now() + interval '7 days'
    );
    RAISE EXCEPTION 'Direct invitation insert unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    UPDATE public.business_invitations
    SET status = 'revoked'
    WHERE id = current_setting('kasbeman.test_invite_id')::uuid;
    RAISE EXCEPTION 'Direct invitation update unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$$;

-- A normal member cannot create invitations or inspect another member's invites.
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';

DO $$
BEGIN
  BEGIN
    PERFORM public.create_business_invitation(
      current_setting('kasbeman.test_business_id')::uuid,
      'other@kasbeman.test',
      'member'
    );
    RAISE EXCEPTION 'Member without team.members.invite created an invitation';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  IF EXISTS (
    SELECT 1 FROM public.business_invitations
    WHERE id = current_setting('kasbeman.test_invite_id')::uuid
  ) THEN
    RAISE EXCEPTION 'Unauthorized member can read another member invitation';
  END IF;
END
$$;

-- A different verified email cannot accept the invitation.
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000006';

DO $$
BEGIN
  BEGIN
    PERFORM public.accept_business_invitation(
      current_setting('kasbeman.test_invite_token')
    );
    RAISE EXCEPTION 'Invitation was accepted by a different email';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$$;

-- The matching verified account can accept once; replay is rejected.
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000005';

SELECT public.accept_business_invitation(
  current_setting('kasbeman.test_invite_token')
) AS accepted_business_id \gset
SELECT set_config('kasbeman.test_accepted_business_id', :'accepted_business_id', false);

DO $$
BEGIN
  IF current_setting('kasbeman.test_accepted_business_id')::uuid <> current_setting('kasbeman.test_business_id')::uuid THEN
    RAISE EXCEPTION 'Invitation accepted into an unexpected business';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.business_members
    WHERE business_id = current_setting('kasbeman.test_business_id')::uuid
      AND user_id = auth.uid()
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Invitation acceptance did not activate membership';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM public.member_role_assignments mra
    JOIN public.roles r
      ON r.business_id = mra.business_id AND r.id = mra.role_id
    WHERE mra.business_id = current_setting('kasbeman.test_business_id')::uuid
      AND mra.user_id = auth.uid()
      AND mra.status = 'active'
      AND r.role_key = 'member'
  ) THEN
    RAISE EXCEPTION 'Invitation acceptance did not assign the invited role';
  END IF;

  BEGIN
    PERFORM public.accept_business_invitation(
      current_setting('kasbeman.test_invite_token')
    );
    RAISE EXCEPTION 'Accepted invitation token was replayed';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$$;

-- Revoked and expired invitations cannot be accepted.
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

SELECT invitation_id AS revoked_invite_id, invitation_token AS revoked_invite_token
FROM public.create_business_invitation(
  :'business_id'::uuid, 'other@kasbeman.test', 'member'
) \gset
SELECT public.revoke_business_invitation(
  :'business_id'::uuid, :'revoked_invite_id'::uuid
);
SELECT set_config('kasbeman.test_revoked_invite_token', :'revoked_invite_token', false);

SELECT invitation_id AS expired_invite_id, invitation_token AS expired_invite_token
FROM public.create_business_invitation(
  :'business_id'::uuid, 'other@kasbeman.test', 'member'
) \gset
RESET ROLE;
UPDATE public.business_invitations
SET created_at = now() - interval '2 minutes',
    expires_at = now() - interval '1 minute'
WHERE id = :'expired_invite_id'::uuid;
SELECT set_config('kasbeman.test_expired_invite_token', :'expired_invite_token', false);

SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000006';

DO $$
BEGIN
  BEGIN
    PERFORM public.accept_business_invitation(
      current_setting('kasbeman.test_revoked_invite_token')
    );
    RAISE EXCEPTION 'Revoked invitation was accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM public.accept_business_invitation(
      current_setting('kasbeman.test_expired_invite_token')
    );
    RAISE EXCEPTION 'Expired invitation was accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$$;

-- Suspending a member revokes every active role assignment immediately.
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

UPDATE public.business_members
SET status = 'suspended'
WHERE business_id = :'business_id'::uuid
  AND user_id = '10000000-0000-4000-8000-000000000002';

RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';

DO $$
DECLARE
  v_updated integer;
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.businesses
    WHERE id = current_setting('kasbeman.test_business_id')::uuid
  ) THEN
    RAISE EXCEPTION 'Suspended member retained tenant access';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.member_role_assignments
    WHERE business_id = current_setting('kasbeman.test_business_id')::uuid
      AND user_id = auth.uid()
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Suspended member retained active role assignments';
  END IF;

  UPDATE public.member_role_assignments
  SET status = 'active', revoked_at = NULL
  WHERE business_id = current_setting('kasbeman.test_business_id')::uuid
    AND user_id = auth.uid()
    AND status = 'revoked';
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated <> 0 THEN
    RAISE EXCEPTION 'Revoked role assignment was reactivated directly';
  END IF;
END
$$;

-- The trigger is a second line of defence even against privileged SQL paths:
-- an owner must use a dedicated ownership-transfer flow, never member suspension.
RESET ROLE;
DO $$
DECLARE
  v_owner_role_assignment_id uuid;
BEGIN
  SELECT mra.id INTO v_owner_role_assignment_id
  FROM public.member_role_assignments mra
  JOIN public.roles r
    ON r.business_id = mra.business_id AND r.id = mra.role_id
  WHERE mra.business_id = current_setting('kasbeman.test_business_id')::uuid
    AND mra.user_id = '10000000-0000-4000-8000-000000000001'
    AND mra.status = 'active'
    AND r.role_key = 'owner';

  BEGIN
    UPDATE public.member_role_assignments
    SET status = 'revoked', revoked_at = now()
    WHERE id = v_owner_role_assignment_id;
    RAISE EXCEPTION 'Owner role assignment was revoked';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    UPDATE public.business_members
    SET status = 'suspended'
    WHERE business_id = current_setting('kasbeman.test_business_id')::uuid
      AND user_id = '10000000-0000-4000-8000-000000000001';
    RAISE EXCEPTION 'Owner membership was suspended';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END
$$;


-- A legacy owner marker must remain protected even if its canonical RBAC
-- owner assignment is missing or inconsistent.
RESET ROLE;
UPDATE public.business_members
SET role_key = 'owner'
WHERE business_id = :'business_id'::uuid
  AND user_id = '10000000-0000-4000-8000-000000000005'
  AND status = 'active';

SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
DO $legacy_owner_guard$
BEGIN
  IF private.can_manage_business_member(
    current_setting('kasbeman.test_business_id')::uuid,
    '10000000-0000-4000-8000-000000000005'::uuid
  ) THEN
    RAISE EXCEPTION 'Legacy owner was considered manageable';
  END IF;
END
$legacy_owner_guard$;

RESET ROLE;
DO $legacy_owner_suspend$
DECLARE
  v_rows integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    WHERE t.tgrelid = 'public.business_members'::regclass
      AND t.tgname = 'business_member_lifecycle_guard'
      AND t.tgenabled = 'O'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'Business member lifecycle guard trigger is missing or disabled';
  END IF;

  BEGIN
    UPDATE public.business_members
    SET status = 'suspended'
    WHERE business_id = current_setting('kasbeman.test_business_id')::uuid
      AND user_id = '10000000-0000-4000-8000-000000000005';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1 THEN
      RAISE EXCEPTION 'Expected one legacy-owner membership row, got %', v_rows;
    END IF;
    RAISE EXCEPTION 'Legacy owner membership was suspended without trigger rejection';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END
$legacy_owner_suspend$;

UPDATE public.business_members
SET role_key = 'member'
WHERE business_id = :'business_id'::uuid
  AND user_id = '10000000-0000-4000-8000-000000000005'
  AND status = 'active';

-- A suspended user can regain access only through a fresh invitation accepted
-- by the same verified account; old role assignments are not restored directly.
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

UPDATE public.business_members
SET status = 'suspended'
WHERE business_id = :'business_id'::uuid
  AND user_id = '10000000-0000-4000-8000-000000000005'
  AND status = 'active';

SELECT invitation_id AS reactivation_invite_id, invitation_token AS reactivation_invite_token
FROM public.create_business_invitation(
  :'business_id'::uuid, 'invitee@kasbeman.test', 'member'
) \gset
SELECT set_config('kasbeman.test_reactivation_token', :'reactivation_invite_token', false);

RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000005';

SELECT public.accept_business_invitation(
  current_setting('kasbeman.test_reactivation_token')
) AS reactivated_business_id \gset

DO $reactivation_check$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.business_members
    WHERE business_id = current_setting('kasbeman.test_business_id')::uuid
      AND user_id = auth.uid()
      AND status = 'active'
      AND role_key = 'member'
  ) THEN
    RAISE EXCEPTION 'Fresh invitation did not reactivate the suspended membership';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.member_role_assignments mra
    JOIN public.roles r
      ON r.business_id = mra.business_id AND r.id = mra.role_id
    WHERE mra.business_id = current_setting('kasbeman.test_business_id')::uuid
      AND mra.user_id = auth.uid()
      AND mra.status = 'active'
      AND r.role_key = 'member'
  ) THEN
    RAISE EXCEPTION 'Fresh invitation did not create a new active role assignment';
  END IF;
END
$reactivation_check$;

-- Only the current sole owner may transfer ownership, and the target must be
-- an already-active member. The transfer is atomic across membership + RBAC.
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';

DO $$
BEGIN
  BEGIN
    PERFORM public.transfer_business_ownership(
      current_setting('kasbeman.test_business_id')::uuid,
      '10000000-0000-4000-8000-000000000004'
    );
    RAISE EXCEPTION 'Suspended non-owner transferred business ownership';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$$;

RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

DO $$
BEGIN
  BEGIN
    PERFORM public.transfer_business_ownership(
      current_setting('kasbeman.test_business_id')::uuid,
      '10000000-0000-4000-8000-000000000002'
    );
    RAISE EXCEPTION 'Ownership was transferred to a suspended member';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    PERFORM public.transfer_business_ownership(
      current_setting('kasbeman.test_business_id')::uuid,
      auth.uid()
    );
    RAISE EXCEPTION 'Owner transferred ownership to themselves';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
END
$$;

-- A second active owner assignment on another active member must block transfer.
RESET ROLE;
DO $$
BEGIN
  BEGIN
    INSERT INTO public.member_role_assignments (
      business_id, user_id, role_id, branch_id, status, assigned_by
    )
    SELECT
      current_setting('kasbeman.test_business_id')::uuid,
      '10000000-0000-4000-8000-000000000004'::uuid,
      r.id, null, 'active',
      '10000000-0000-4000-8000-000000000001'::uuid
    FROM public.roles r
    WHERE r.business_id = current_setting('kasbeman.test_business_id')::uuid
      AND r.role_key = 'owner'
      AND r.is_system
      AND r.status = 'active';

    PERFORM public.transfer_business_ownership(
      current_setting('kasbeman.test_business_id')::uuid,
      '10000000-0000-4000-8000-000000000004'
    );
    RAISE EXCEPTION 'Transfer ignored an additional active owner assignment';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END
$$;

-- An active legacy owner membership without a matching owner assignment must
-- also make the ownership state inconsistent and block transfer.
DO $$
BEGIN
  BEGIN
    UPDATE public.business_members
    SET role_key = 'owner'
    WHERE business_id = current_setting('kasbeman.test_business_id')::uuid
      AND user_id = '10000000-0000-4000-8000-000000000005'
      AND status = 'active';

    PERFORM public.transfer_business_ownership(
      current_setting('kasbeman.test_business_id')::uuid,
      '10000000-0000-4000-8000-000000000004'
    );
    RAISE EXCEPTION 'Transfer ignored an extra legacy owner membership';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END
$$;

-- The canonical owner assignment must be business-wide, not branch-scoped.
DO $$
DECLARE
  v_business_id uuid := current_setting('kasbeman.test_business_id')::uuid;
  v_transfer_role_id uuid;
BEGIN
  BEGIN
    -- Add a temporary business-wide transfer permission first, while the
    -- original owner grant is still valid, so the function reaches its
    -- ownership-state validation after the owner grant becomes branch-scoped.
    INSERT INTO public.roles (business_id, role_key, name, is_system, status, created_by)
    VALUES (v_business_id, 'transfer_test', 'Transfer Test', false, 'active', auth.uid())
    RETURNING id INTO v_transfer_role_id;

    INSERT INTO public.role_permissions (business_id, role_id, permission_key)
    VALUES
      (v_business_id, v_transfer_role_id, 'team.roles.assign'),
      (v_business_id, v_transfer_role_id, 'business.ownership.transfer');

    INSERT INTO public.member_role_assignments (
      business_id, user_id, role_id, branch_id, status, assigned_by
    ) VALUES (
      v_business_id, auth.uid(), v_transfer_role_id, null, 'active', auth.uid()
    );

    UPDATE public.member_role_assignments mra
    SET branch_id = (
      SELECT b.id FROM public.branches b
      WHERE b.business_id = mra.business_id AND b.is_primary
      LIMIT 1
    )
    FROM public.roles r
    WHERE mra.business_id = v_business_id
      AND mra.user_id = auth.uid()
      AND mra.status = 'active'
      AND r.business_id = mra.business_id
      AND r.id = mra.role_id
      AND r.role_key = 'owner'
      AND r.is_system;

    PERFORM public.transfer_business_ownership(
      v_business_id,
      '10000000-0000-4000-8000-000000000004'
    );
    RAISE EXCEPTION 'Transfer accepted a branch-scoped owner assignment';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END
$$;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';

SELECT public.transfer_business_ownership(
  current_setting('kasbeman.test_business_id')::uuid,
  '10000000-0000-4000-8000-000000000004'
) AS transferred_owner_id \gset
SELECT set_config('kasbeman.test_transferred_owner_id', :'transferred_owner_id', false);

DO $$
DECLARE
  v_business_id uuid := current_setting('kasbeman.test_business_id')::uuid;
  v_new_owner_id uuid := current_setting('kasbeman.test_transferred_owner_id')::uuid;
  v_old_owner_id uuid := '10000000-0000-4000-8000-000000000001';
BEGIN
  IF v_new_owner_id <> '10000000-0000-4000-8000-000000000004'::uuid THEN
    RAISE EXCEPTION 'Ownership transfer returned the wrong owner';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.business_members
    WHERE business_id = v_business_id
      AND user_id = v_new_owner_id
      AND status = 'active'
      AND role_key = 'owner'
  ) THEN
    RAISE EXCEPTION 'New owner membership was not updated';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.business_members
    WHERE business_id = v_business_id
      AND user_id = v_old_owner_id
      AND status = 'active'
      AND role_key = 'admin'
  ) THEN
    RAISE EXCEPTION 'Previous owner was not retained as an active admin';
  END IF;

  IF (
    SELECT count(*)
    FROM public.member_role_assignments mra
    JOIN public.roles r
      ON r.business_id = mra.business_id AND r.id = mra.role_id
    WHERE mra.business_id = v_business_id
      AND mra.status = 'active'
      AND r.role_key = 'owner'
  ) <> 1 THEN
    RAISE EXCEPTION 'Transfer did not preserve exactly one active owner';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.member_role_assignments mra
    JOIN public.roles r
      ON r.business_id = mra.business_id AND r.id = mra.role_id
    WHERE mra.business_id = v_business_id
      AND mra.user_id = v_new_owner_id
      AND mra.status = 'active'
      AND r.role_key = 'owner'
      AND mra.branch_id IS NULL
  ) THEN
    RAISE EXCEPTION 'New owner RBAC assignment is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.member_role_assignments mra
    JOIN public.roles r
      ON r.business_id = mra.business_id AND r.id = mra.role_id
    WHERE mra.business_id = v_business_id
      AND mra.user_id = v_old_owner_id
      AND mra.status = 'active'
      AND r.role_key = 'admin'
      AND mra.branch_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Previous owner did not receive the admin role';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.member_role_assignments mra
    JOIN public.roles r
      ON r.business_id = mra.business_id AND r.id = mra.role_id
    WHERE mra.business_id = v_business_id
      AND mra.user_id = v_new_owner_id
      AND mra.status = 'active'
      AND r.role_key <> 'owner'
  ) THEN
    RAISE EXCEPTION 'New owner retained stale role assignments';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.member_role_assignments mra
    JOIN public.roles r
      ON r.business_id = mra.business_id AND r.id = mra.role_id
    WHERE mra.business_id = v_business_id
      AND mra.user_id = v_old_owner_id
      AND mra.status = 'active'
      AND r.role_key <> 'admin'
  ) THEN
    RAISE EXCEPTION 'Previous owner retained additional role assignments';
  END IF;

  IF private.has_business_permission(v_business_id, 'business.ownership.transfer', null) THEN
    RAISE EXCEPTION 'Previous owner retained ownership transfer permission';
  END IF;
END
$$;

RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '10000000-0000-4000-8000-000000000004';

DO $$
BEGIN
  IF NOT private.has_business_permission(
    current_setting('kasbeman.test_business_id')::uuid,
    'business.ownership.transfer',
    null
  ) THEN
    RAISE EXCEPTION 'New owner did not receive ownership authority';
  END IF;
END
$$;

SELECT 'Membership lifecycle and invitation hardening checks passed.' AS result;

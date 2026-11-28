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
SET expires_at = now() - interval '1 minute'
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
BEGIN
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

SELECT 'Membership lifecycle and invitation hardening checks passed.' AS result;

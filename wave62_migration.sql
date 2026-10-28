-- Wave 62: team invites actually work.
-- An invited person could never join: the pending invite has no user_id yet, and the update policy only
-- lets admins or the row's own user change it, so the app's "link my invite" update silently did nothing.
-- This function links every pending invite for the signed-in user's confirmed email address.
create or replace function public.cc_accept_invites()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer := 0;
  em text;
begin
  if auth.uid() is null then return 0; end if;
  select lower(u.email) into em from auth.users u where u.id = auth.uid() and u.email_confirmed_at is not null;
  if em is null then return 0; end if;
  update public.cc_company_members
     set user_id = auth.uid(), status = 'active'
   where lower(email) = em and status = 'pending' and (user_id is null or user_id = auth.uid());
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.cc_accept_invites() from public, anon;
grant execute on function public.cc_accept_invites() to authenticated;

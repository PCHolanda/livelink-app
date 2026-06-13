import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

    // Get Auth token from headers
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing Authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Initialize regular Supabase client to verify the caller
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    })

    // Get calling user details
    const { data: { user }, error: userError } = await supabase.auth.getUser()
    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid user session: ' + (userError?.message || '') }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Initialize service role client for privileged operations
    const adminSupabase = createClient(supabaseUrl, supabaseServiceKey)

    // Check if caller is admin in public.users table
    const { data: profile, error: profileError } = await adminSupabase
      .from('users')
      .select('role, active')
      .eq('id', user.id)
      .single()

    if (profileError || !profile || profile.role !== 'admin' || !profile.active) {
      return new Response(
        JSON.stringify({ error: 'Access denied: User is not an active administrator' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Parse request body
    const { action, payload } = await req.json()

    if (action === 'create') {
      const { email, password, name, role } = payload
      
      // Create user in auth
      const { data: newAuthUser, error: createError } = await adminSupabase.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { name, role, active: true }
      })

      if (createError || !newAuthUser.user) {
        return new Response(
          JSON.stringify({ error: 'Failed to create user in Auth: ' + (createError?.message || '') }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      // Return the newly created user (trigger on_auth_user_created handles insertion in public.users)
      return new Response(
        JSON.stringify({ message: 'User created successfully', user: newAuthUser.user }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )

    } else if (action === 'update') {
      const { id, email, name, role, active } = payload

      // Update auth details
      const { data: _, error: updateAuthError } = await adminSupabase.auth.admin.updateUserById(id, {
        email,
        user_metadata: { name, role, active }
      })

      if (updateAuthError) {
        return new Response(
          JSON.stringify({ error: 'Failed to update user in Auth: ' + updateAuthError.message }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      // Also update public.users directly to sync role, active, name
      const { error: updateDbError } = await adminSupabase
        .from('users')
        .update({ name, role, active })
        .eq('id', id)

      if (updateDbError) {
        return new Response(
          JSON.stringify({ error: 'Failed to update user in Database: ' + updateDbError.message }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      return new Response(
        JSON.stringify({ message: 'User updated successfully' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )

    } else if (action === 'delete') {
      const { id } = payload

      // Delete user from auth (will cascade delete from public.users)
      const { error: deleteError } = await adminSupabase.auth.admin.deleteUser(id)

      if (deleteError) {
        return new Response(
          JSON.stringify({ error: 'Failed to delete user: ' + deleteError.message }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      return new Response(
        JSON.stringify({ message: 'User deleted successfully' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )

    } else if (action === 'reset-password') {
      const { id, newPassword } = payload

      // Update password in Auth
      const { error: resetError } = await adminSupabase.auth.admin.updateUserById(id, {
        password: newPassword
      })

      if (resetError) {
        return new Response(
          JSON.stringify({ error: 'Failed to reset password: ' + resetError.message }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      return new Response(
        JSON.stringify({ message: 'Password reset successfully' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )

    } else {
      return new Response(
        JSON.stringify({ error: 'Unsupported action: ' + action }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { AccessToken } from "npm:livekit-server-sdk"

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
    const { roomName, identity, isPublisher } = await req.json()

    if (!roomName || !identity) {
      return new Response(
        JSON.stringify({ error: 'roomName and identity are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const apiKey = Deno.env.get('LIVEKIT_API_KEY')
    const apiSecret = Deno.env.get('LIVEKIT_API_SECRET')
    const livekitUrl = Deno.env.get('LIVEKIT_URL')

    if (!apiKey || !apiSecret || !livekitUrl) {
      return new Response(
        JSON.stringify({ error: 'LiveKit credentials are not configured on the Supabase backend.' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Instantiate LiveKit access token
    const at = new AccessToken(apiKey, apiSecret, {
      identity: identity,
      ttl: '2h', // 2 hour session duration
    })

    const publisher = isPublisher === true || isPublisher === 'true'

    // Configure room permissions
    at.addGrant({
      roomJoin: true,
      room: roomName,
      canPublish: publisher,
      canSubscribe: true,
      roomCreate: publisher,
    })

    const token = await at.toJwt()

    return new Response(
      JSON.stringify({ token, url: livekitUrl }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

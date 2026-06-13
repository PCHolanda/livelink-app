import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { create, getNumericDate } from "https://deno.land/x/djwt@v2.8/mod.ts"

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

    const publisher = isPublisher === true || isPublisher === 'true'

    // Create HMAC SHA-256 Key for JWT Signing
    const encoder = new TextEncoder()
    const keyData = encoder.encode(apiSecret)
    const key = await crypto.subtle.importKey(
      "raw",
      keyData,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"]
    )

    // Build standard LiveKit Access Token Claims
    const payload = {
      iss: apiKey,
      sub: identity,
      nbf: getNumericDate(0),
      exp: getNumericDate(2 * 60 * 60), // Valid for 2 hours
      video: {
        room: roomName,
        roomJoin: true,
        roomCreate: publisher,
        canPublish: publisher,
        canSubscribe: true,
      }
    }

    // Sign the token using native Web Crypto API via djwt
    const token = await create({ alg: "HS256", typ: "JWT" }, payload, key)

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

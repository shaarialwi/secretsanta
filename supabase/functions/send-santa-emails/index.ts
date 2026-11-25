import { createClient } from "npm:@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
function response(data:unknown,status=200){return new Response(JSON.stringify(data),{status,headers:{...cors,"Content-Type":"application/json"}})}
Deno.serve(async(req)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return response({error:"Method not allowed"},405);
 try{
 const token=req.headers.get("Authorization");if(!token?.startsWith("Bearer "))return response({error:"Sign in first"},401);
 const db=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_ANON_KEY")!,{global:{headers:{Authorization:token}},auth:{persistSession:false}});
 const {data:user,error:authError}=await db.auth.getUser(token.slice(7));if(authError||!user.user)return response({error:"Invalid session"},401);
 const {code}=await req.json();if(typeof code!=="string"||!/^[A-F0-9]{10}$/i.test(code))return response({error:"Invalid room code"},400);
 const {data:state,error}=await db.rpc("santa_game",{action:"state",payload:{code}});
 if(error||!state?.host||!state.registration_only)return response({error:"Moderator access required"},403);
 if(state.phase==="lobby")return response({error:"Run the private draw first"},400);
 const api=Deno.env.get("RESEND_API_KEY"),from=Deno.env.get("SANTA_FROM_EMAIL");
 if(!api||!from)return response({error:"Email service not configured. Set RESEND_API_KEY and SANTA_FROM_EMAIL in Supabase Edge Function secrets."},503);
 if(state.players.some((p:any)=>!p.email||!p.recipient))return response({error:"Every participant needs an email and assignment."},400);
 let sent=0;const failed:string[]=[];
 for(const p of state.players){
 if(p.sent_at)continue;
 const body:any={from,to:[p.email],subject:"Your private Secret Santa assignment",text:["Hi "+p.name+",","","You are the Secret Santa for: "+p.recipient,"Gift budget: "+state.budget,"Wishlist: "+(p.recipient_wish||"No wishlist provided"),p.recipient_photo?"A gift picture is attached.":"","Please keep your assignment confidential. Happy gifting!","","Strategy Division Secret Santa"].join("\n")};
 if(p.recipient_photo?.startsWith("data:image/jpeg;base64,"))body.attachments=[{filename:"gift-wishlist.jpg",content:p.recipient_photo.split(",")[1]}];
 try{
 const result=await fetch("https://api.resend.com/emails",{method:"POST",headers:{Authorization:"Bearer "+api,"Content-Type":"application/json","Idempotency-Key":"santa/"+state.code+"/"+p.uid},body:JSON.stringify(body)});
 if(!result.ok){failed.push(p.name+": email provider rejected request ("+result.status+")");continue;}
 const marked=await db.rpc("santa_game",{action:"mark_sent",payload:{code,uid:p.uid}});
 if(marked.error){failed.push(p.name+": accepted by email provider; status update failed. Check provider logs before retrying.");continue;}
 sent++;
 }catch{failed.push(p.name+": email request failed; check provider logs before retrying");}
 await new Promise(r=>setTimeout(r,550));
 }
 return response({sent,failed});
 }catch{return response({error:"Unable to process email request"},500)}
});

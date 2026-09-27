(function(){
  const url = "https://jwtxilcbbbaqnvoxigmu.supabase.co";
  const stored = localStorage.getItem("jsf_mafigo_supabase_publishable_key") || "";
  window.SUPABASE_CONFIG = { url, publishableKey: stored };
})();

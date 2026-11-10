// The FieldOS cloud this dashboard reads. Both values are public by design
// (the same ones the app ships with); row-level security on the server
// decides what each signed-in person can see. Filled in when the website
// is deployed (see website/README.md, "Owner dashboard").
window.FIELDOS_CLOUD = {
  url: '',      // https://<project-ref>.supabase.co
  anonKey: '',  // the project's anon (public) key
};

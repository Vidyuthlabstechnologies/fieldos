import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Served at https://fieldos-mldynamic.netlify.app/office/ (the website's own
// address), so the built files expect to live under /office/.
export default defineConfig({
  base: '/office/',
  plugins: [react()],
});

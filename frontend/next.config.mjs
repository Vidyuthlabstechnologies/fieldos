/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "export",
  // Emit page/index.html (not page.html) for every route -- this is the
  // layout FastAPI's StaticFiles(html=True) needs to resolve clean URLs
  // like /project without any custom routing code in desktop_app.py.
  trailingSlash: true,
};

export default nextConfig;

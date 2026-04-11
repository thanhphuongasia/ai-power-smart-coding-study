import { createApp } from "./index.js";

const port = Number(process.env.PORT || 8788);
const app = createApp();

app.listen(port, () => {
  console.log(`App API listening on http://127.0.0.1:${port}`);
  console.log(`Admin web available at http://127.0.0.1:${port}/admin`);
});

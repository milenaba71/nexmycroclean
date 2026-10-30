import { handle } from './handler.js';
Deno.serve(req => handle(req, name => Deno.env.get(name)));

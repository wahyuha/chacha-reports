import adapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

export default {
	preprocess: vitePreprocess(),
	kit: {
		// Client-side only: every path serves index.html and the app routes in the browser.
		adapter: adapter({ fallback: 'index.html' })
	}
};

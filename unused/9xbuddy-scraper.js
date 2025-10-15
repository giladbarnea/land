const { NinexbuddyScraper } = require('ninexbuddy-scraper');
(async () => {
	const url = 'https://9xbuddy.in/process?url=https://www.youtube.com/watch?v=nwgcwfTC4xM';
	const scrap = await new NinexbuddyScraper().scrap(url);
	console.log(scrap)
	if(scrap.success)
		console.log(scrap.data.sources);
})();
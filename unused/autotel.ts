// ts-node autotel.ts
import * as nodefetch from 'node-fetch';
// const nodefetch = require('node-fetch');
import * as fs from 'fs';
// const fs = require('fs');
import * as util from 'util';
// const util = require('util');
import { spawnSync } from 'child_process';
// const { spawnSync } = require('child_process');

const argv = process.argv.slice(2);
let maxdistance = 1;
let once = false;
if (argv.length > 1) {
	console.log(argv);
	for (let arg of argv) {
		if (arg.startsWith('--dist=')) {
			maxdistance = parseFloat(arg.split("=")[1]);
		} else if (arg == '--reset') {
			fs.writeFileSync('./autotel.json', JSON.stringify([]));
			console.log(`Reset ./autotel.json`);
		} else if (arg == '--once') {
			once = true;
		}
	}
}
console.log(`maxdistance: ${maxdistance}`);
interface Car { info: CarInfo, items: { [index: number]: CarItem; }; }
interface CarInfo {
	activeCarHere: boolean,
	distance: number, // float
	inactive: boolean,
	showMarker: boolean,
	parkingAddress: [{ languageId: 0, text: string; }, { languageId: 1, text: string; }]; // 0 eng, 1 heb
}
interface CarItem {
	status,
	addressEn: string,
	addressHe: string,
	display: boolean,
	distance: number, // float
	licensePlate: string,
	parkingAddress: string, // eng
	carId: number;

}
interface MyCar { where: string, dist: number; }
const url = "https://reserve.autotel.co.il/reservation/cars/ajax";
const csrftoken_base = "SERiNWJ6YmkedC9gFgo9DioDVH5bA1JYODQjQjYeJz8pElQNNBs9RA";
const csrftoken = `${csrftoken_base}==`;
const csrftoken_percent = `${csrftoken_base}%3D%3D`;
const headers = {
	"accept": "*/*",
	"accept-language": "en-US,en;q=0.9,he;q=0.8",
	"cache-control": "no-cache",
	"content-type": "application/x-www-form-urlencoded; charset=UTF-8",
	"pragma": "no-cache",
	"sec-ch-ua": "\"Google Chrome\";v=\"87\", \" Not;A Brand\";v=\"99\", \"Chromium\";v=\"87\"",
	"sec-ch-ua-mobile": "?0",
	"sec-fetch-dest": "empty",
	"sec-fetch-mode": "cors",
	"sec-fetch-site": "same-origin",
	"x-csrf-token": csrftoken,
	"x-requested-with": "XMLHttpRequest",
	"cookie": "_lang=4478ca18fa754bb47f3c1c6fe854d5c1cd61476f9042b6f5476a93f0ac6663f4a%3A2%3A%7Bi%3A0%3Bs%3A5%3A%22_lang%22%3Bi%3A1%3Bs%3A5%3A%22he-IL%22%3B%7D; vspirits_status=inprocess; _csrf=f5030c631891d6e8c424115150f6092d5c5e5ea603b130a6846812eacd829a49a%3A2%3A%7Bi%3A0%3Bs%3A5%3A%22_csrf%22%3Bi%3A1%3Bs%3A32%3A%22V0MUtp_gbG6K9y01ppAwTdEVaV68Va_-%22%3B%7D; PHPSESSID=usojmjjpvnb3l4il051b2r68h5; _identity=821eb8f1c624144f5b78a26bc909e43d5fadcbb1bb0691ab58e02a6c548b4453a%3A2%3A%7Bi%3A0%3Bs%3A9%3A%22_identity%22%3Bi%3A1%3Bs%3A22%3A%22%5B9027153%2Cnull%2C2592000%5D%22%3B%7D; firstEventFB=1"
};
async function magic(){
	const res = await nodefetch(url, {
		headers,
		"referrer": "https://reserve.autotel.co.il/reservation",
		"referrerPolicy": "strict-origin-when-cross-origin",
		"body": `_csrf=${csrftoken_percent}&Profile%5Bloss_damage_waiver%5D=0&ReservationHelper%5BstartDate%5D=&ReservationHelper%5BendDate%5D=&ReservationHelper%5Baddress%5D=%D7%9E%D7%9C%D7%A6'%D7%98+47%2C+%D7%AA%D7%9C+%D7%90%D7%91%D7%99%D7%91+%D7%99%D7%A4%D7%95%2C+%D7%99%D7%A9%D7%A8%D7%90%D7%9C&ReservationHelper%5Bflex_time%5D=&ReservationHelper%5Blatitude%5D=32.0719825&ReservationHelper%5Blongitude%5D=34.7766267&ReservationHelper%5Bmember_credentials%5D=`,
		"method": "POST",
		"mode": "cors"
	});
	const data = await res.json();
	const cars: Car[] = data.cars;
	const activeCars: Car[] = cars
		.filter(_c => _c.info.activeCarHere && !_c.info.inactive && _c.info.distance < maxdistance)
		.sort((_c1, _c2) => _c1.info.distance - _c2.info.distance);

	const myCars: MyCar[] = [];
	for (let car of activeCars) {
		const { distance, parkingAddress } = car.info;
		const where = parkingAddress[0].text;
		myCars.push({ where, dist: distance });
	}
	const prevData: MyCar[] = JSON.parse(fs.readFileSync('./autotel.json').toString());
	const changed = !util.isDeepStrictEqual(myCars, prevData);
	let color = myCars.length > prevData.length ? 32 : myCars.length < prevData.length ? 31 : 0;

	console.log(`\x1b[${color}mCHANGE: `, changed);
	console.log(`\nCURRENT CAR COUNT: ${activeCars.length}\x1b[0m`);
	if (prevData.length != myCars.length) {
		console.log(`LAST CAR COUNT: ${prevData.length}`);
	}
	console.log();
	if (changed) {
		
		const newcars: MyCar[] = [];
		for (let this_iteration_car of myCars) {
			let known = false;
			for (let prev_iteration_car of prevData) {
				if (!known && util.isDeepStrictEqual(this_iteration_car, prev_iteration_car)) {
					known = true;
				}
			}
			if (!known) {
				console.log(`\x1b[32;1mNEW CAR:\x1b[0m`, this_iteration_car);

				newcars.push(this_iteration_car);

			}
		}
		console.log('Cars right now: ', myCars);
		console.log('Cars last check: ', prevData);
		fs.writeFileSync('./autotel.json', JSON.stringify(myCars));
		if(newcars.length >1){
		const zenitystr = `zenity --list --title="New Cars" --width=1000 --height=700 --column "Address" --column "Distance (km)"`;
		const newcarsstr = newcars.map(c => `'${c.where.split("'").join().split('"').join()}' ${c.dist}`).join(" ");
		const rv = spawnSync(`${zenitystr} ${newcarsstr}`, { shell: true });
		console.log(`rv.output: `, rv.output.map(x => {
			try{ return x.toString()}catch(e){return x}
		}));}
	} else if (myCars.length > 1) {
		console.log(myCars);
	}
}
(async () => {
	
	while (true) {
		
		await magic();
		if (once){
			return
		}

		let ms = Math.random() * 30000; // avg 15s
		while (ms < 5000 || ms > 30000) {
			ms = Math.random() * 30000;
		}
		console.log(`\n\n\x1b[1mWaiting ${ms / 1000}s...\x1b[0m`);
		await new Promise(resolve => setTimeout(resolve, ms));

	}
})();


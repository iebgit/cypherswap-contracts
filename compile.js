const path = require("path");
const fs = require("fs");
const solc = require("solc");

const strategyPath = path.resolve(__dirname, "contracts", "Strategy.sol");
const source = fs.readFileSync(strategyPath, "utf8");
module.exports = solc.compile(source, 1).contracts[":Strategy"];
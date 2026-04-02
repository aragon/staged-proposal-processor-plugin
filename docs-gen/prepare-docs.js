const docgen = require("solidity-docgen/dist/main");

const { readdir } = require("node:fs/promises");
const { join } = require("node:path");
const path = require("path");
const fs = require("fs-extra");
const solc = require("solc");
const glob = require("glob");
const startCase = require("lodash.startcase");
const { version, repository } = require("./package.json");

const ROOT_DIR = path.resolve(__dirname, "..");

const walk = async (dirPath) =>
    Promise.all(
        await readdir(dirPath, { withFileTypes: true }).then((entries) =>
            entries.map((entry) => {
                const childPath = join(dirPath, entry.name);
                return entry.isDirectory() ? walk(childPath) : childPath;
            }),
        ),
    );

let includePaths = [path.join(__dirname, "node_modules")];

function resolveImports(filePath) {
    for (const includePath of includePaths) {
        const fullPath = path.resolve(includePath, filePath);
        if (fs.existsSync(fullPath)) {
            return { contents: fs.readFileSync(fullPath, "utf8") };
        }
    }
    return { error: `File not found: ${filePath}` };
}

const compile = async (filePaths) => {
    const compilerInput = {
        language: "Solidity",
        sources: filePaths.reduce((input, fileName) => {
            const source = fs.readFileSync(fileName, "utf8");
            return { ...input, [fileName]: { content: source } };
        }, {}),
        settings: {
            outputSelection: {
                "*": {
                    "*": ["*"],
                    "": ["ast"],
                },
            },
        },
    };

    return {
        output: JSON.parse(
            solc.compile(JSON.stringify(compilerInput), {
                import: resolveImports,
            }),
        ),
        input: compilerInput,
    };
};

function generateNav(pagesDir) {
    const files = glob
        .sync(pagesDir + "/**/*.adoc")
        .map((f) => path.relative(pagesDir, f));

    function getPageTitle(name) {
        switch (name) {
            case "metatx": return "Meta Transactions";
            case "common": return "Common (Tokens)";
            default: return startCase(name);
        }
    }

    const links = files
        .map((file) => ({ xref: `* xref:${file}[${getPageTitle(path.parse(file).name)}]`, title: path.parse(file).name }))
        .sort((a, b) => a.title.toLowerCase().localeCompare(b.title.toLowerCase(), undefined, { numeric: true }));

    return [".API", ...links.map((l) => l.xref)].join("\n") + "\n";
}

async function main() {
    const contractPath = path.resolve(ROOT_DIR, "src");
    const allFiles = await walk(contractPath);

    const solFiles = allFiles.flat(Number.POSITIVE_INFINITY).filter((item) => {
        return path.extname(item).toLowerCase() == ".sol";
    });

    const { input, output } = await compile(solFiles);

    const templatesPath = path.resolve(ROOT_DIR, "docs/templates");
    const apiPath = path.resolve(ROOT_DIR, "docs/modules/api");

    const helpers = require(path.join(templatesPath, "helpers"));

    // overwrite the functions.
    helpers.version = () => `${version}`;
    helpers.githubURI = () => repository.url;

    const config = {
        outputDir: `${apiPath}/pages`,
        sourcesDir: contractPath,
        templates: templatesPath,
        exclude: ["mocks", "test"],
        pageExtension: ".adoc",
        collapseNewlines: true,
        pages: (_, file, config) => {
            return "StagedProposalProcessor" + config.pageExtension;
        },
    };

    await docgen.main([{ input: input, output: await output }], config);

    fs.writeFileSync(`${apiPath}/nav.adoc`, generateNav(`${apiPath}/pages`), "utf8");

    fs.rm(templatesPath, { recursive: true, force: true }, () => {});
}

main();

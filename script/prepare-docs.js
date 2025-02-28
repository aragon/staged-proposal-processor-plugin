const docgen = require('solidity-docgen/dist/main');

const { readdir } = require('node:fs/promises')
const { join } = require('node:path')
const path = require('path');
const fs = require("fs-extra");
const solc = require("solc");
const { execSync } = require('child_process');
const { version, repository } = require('../package.json');

const ROOT_DIR = path.resolve(__dirname, '..')

const walk = async (dirPath) => Promise.all(
    await readdir(dirPath, { withFileTypes: true }).then((entries) => entries.map((entry) => {
        const childPath = join(dirPath, entry.name)
        return entry.isDirectory() ? walk(childPath) : childPath
    })),
)

let includePaths = ['node_modules']

function resolveImports(filePath) {
    for (const includePath of includePaths) {
        const fullPath = path.resolve(ROOT_DIR, path.join(includePath, filePath));
        if (fs.existsSync(fullPath)) {
            return { contents: fs.readFileSync(fullPath, 'utf8') };
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
                    '*': ['*'],
                    "": [
                        "ast"
                    ]
                },
            },
        },
    };

    return {
        output: JSON.parse(solc.compile(JSON.stringify(compilerInput), {
            import: resolveImports,
        })),
        input: compilerInput
    }
}

async function main() {
    const contractPath = path.resolve(ROOT_DIR, "src");
    const allFiles = await walk(contractPath);

    const solFiles = allFiles.flat(Number.POSITIVE_INFINITY).filter(item => {
        return path.extname(item).toLowerCase() == '.sol'
    })

    const { input, output } = await compile(solFiles)

    const templatesPath = 'docs/templates'
    const apiPath = 'docs/modules/api'

    const helpers = require(path.resolve(ROOT_DIR, 'docs/templates/helpers'))

    // overwrite the functions.
    helpers.version = () => `${version}`;
    helpers.githubURI = () => repository.url;

    const config = {
        outputDir: `${apiPath}/pages`,
        sourcesDir: path.resolve(ROOT_DIR, "src"),
        templates: templatesPath,
        exclude: ['mocks', 'test'],
        pageExtension: '.adoc',
        collapseNewlines: true,
        pages: (_, file, config) => {
            return 'StagedProposalProcessor' + config.pageExtension;
        },
    };

    await docgen.main([{ input: input, output: await output }], config);

    const navOutput = execSync(`node script/gen-nav.js ${apiPath}/pages`, { encoding: 'utf8' });

    // Write the output to the target file
    const targetFilePath = `${apiPath}/nav.adoc`;
    fs.writeFileSync(targetFilePath, navOutput, 'utf8');

    fs.rm(templatesPath, { recursive: true, force: true }, () => { })
}

main()
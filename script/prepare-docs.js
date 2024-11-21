const docgen = require('solidity-docgen/dist/main');

const {readdir} = require('node:fs/promises')
const {join} = require('node:path')
const path = require('path');
const fs = require("fs-extra");
const solc = require("solc");

const walk = async (dirPath) => Promise.all(
  await readdir(dirPath, { withFileTypes: true }).then((entries) => entries.map((entry) => {
    const childPath = join(dirPath, entry.name)
    return entry.isDirectory() ? walk(childPath) : childPath
  })),
)

let includePaths = ['node_modules']

function resolveImports(filePath) {
    for (const includePath of includePaths) {
      const fullPath = path.resolve(__dirname, '..', path.join(includePath, filePath));
      if (fs.existsSync(fullPath)) {
        return { contents: fs.readFileSync(fullPath, 'utf8') };
      }
    }
    return { error: `File not found: ${filePath}` };
  }

const compile = async(filePaths) => {
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

    const compiled = JSON.parse(solc.compile(JSON.stringify(compilerInput), {
        import: resolveImports,
    }));
    // console.log(compiled.contracts['/Users/giorgilagidze/Desktop/work/multibody/staged-proposal-processor-plugin/src/StagedProposalProcessor.sol'])
    return compiled;
}

async function main() {
    const contractPath = path.resolve(__dirname, "../src");
    const allFiles = await walk(contractPath);

    const solFiles = allFiles.flat(Number.POSITIVE_INFINITY).filter(item => {
        return path.extname(item).toLowerCase() == '.sol'
    })

    const compiled = compile(solFiles)

    const config =  {
        outputDir: 'docs/modules/api/pages',
        sourcesDir: path.resolve(__dirname, "../src"),
        templates: 'docs/templates',
        exclude: ['mocks', 'test'],
        pageExtension: '.adoc',
        collapseNewlines: true,
        pages: (_, file, config) => {
            return 'SPP' + config.pageExtension;
        },
    };

    await docgen.main([{ output: await compiled }], config);
} 

main()






  





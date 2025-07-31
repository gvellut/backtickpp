import { HelperProcess } from './extension';

async function main() {
    console.log('Starting CLI test for Backtick++ Helper...');
    const helper = new HelperProcess();

    try {

        console.log('Getting windows...');
        const windows = await helper.getWindows('top', 'automatic');
        console.log('Windows found:', windows);

    } catch (error) {
        console.error('An error occurred:', error);
    }
    debugger;
}

main();

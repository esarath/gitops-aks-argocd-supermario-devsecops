module.exports = {
    testEnvironment: 'node',
    collectCoverage: true,
    collectCoverageFrom: ['webapp/code/multiple.js'],
    coverageReporters: ['lcov', 'text'],
    coverageDirectory: 'coverage'
};

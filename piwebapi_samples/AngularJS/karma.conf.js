//jshint strict: false
module.exports = function(config) {
  config.set({
    client: {
      jasmine: {
        random: false
      }
    },

    basePath: './app',

    files: [
      '../test-config.js',
      'lib/angular/angular.js',
      'lib/angular-route/angular-route.js',
      '../node_modules/angular-mocks/angular-mocks.js',
      '*.js'
    ],

    autoWatch: true,

    frameworks: ['jasmine'],

    browsers: ['Chrome'],

    plugins: ['karma-chrome-launcher', 'karma-jasmine', 'karma-junit-reporter'],

    singleRun: true,

    reporters: ['progress', 'junit'],

    junitReporter: {
      outputDir: './junitResults',
      suite: '',
      useBrowserName: true,
      nameFormatter: undefined,
      classNameFormatter: undefined,
      properties: {}
    }
  });
};

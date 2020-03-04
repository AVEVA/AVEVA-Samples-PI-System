
(function (PV) {
	'use strict';

	function symbolVis() { }
    PV.deriveVisualizationFromBase(symbolVis);

    var definition = {
        typeName: 'Arrow',
        visObjectType: symbolVis,
        datasourceBehavior: PV.Extensibility.Enums.DatasourceBehaviors.Single,
        supportsCollections: true,
        iconUrl: 'scripts/app/editor/symbols/ext/icons/sym-arrow.png',
        getDefaultConfig: function () {
            return {
                // Changing these values in code will cause addtional undo levels to be created
                // They should only be updated by config.html using Angular ng-model
                DataShape: 'Gauge',
                ValueScale: false,
                ValueScaleSettings: {
                    MinType: 2,
                    MinValue: 0,
                    MaxType: 2,
                    MaxValue: 360
                },
                Height: 80,
                Width: 80,
                ShowLabel: false,
                ShowValue: true,
                ShowTimestamp: false,
                LabelColor: 'grey',
                ValueColor: 'white',
                ArrowDefaultColor: 'green',
                LabelType: 'Full'
            };
        },
        StateVariables: ['MultistateColor'],
        configOptions: function () {
            return [{
                title: 'Format Wind Arrow',
                mode: 'formatWindArrow'
            }];
        }
    };

    symbolVis.prototype.init = function (scope, elem) {
        scope.showText = true;
        scope.Value = '';
        scope.Timestamp = '';
        scope.Width;
        scope.Height;
        scope.Label = '';

        // runtimeData is passed to config.html and can be changed in code without causing additional undo levels
        // The labelOptions are used to populate the label dropdown listbox on the config.html display
        scope.runtimeData.labelOptions = '';

        this.onDataUpdate = onDataUpdate;
        this.onResize = onResize;
        this.onConfigChange = onConfigChange;

        // Update symbol with new data
        function onDataUpdate(newData) {
            if (!newData) {
                return;
            }

            // Set labels if provided in update data
            // Metadata fields are returned on the first request and only periodically afterward
            if (newData.Label !== undefined) {
                setLabelOptions(newData.Label);
                if (newData.Units !== undefined) {
                    scope.Units = newData.Units;
                } else {
                    scope.Units = '';
                }
            }
            scope.Value = newData.Value;
            scope.Timestamp = newData.Time;

            // Rotate the arrow
            var svgArrow = elem.find('.svg-arrow')[0];
            var Degrees = 360 * newData.Indicator / 100;
            svgArrow.setAttribute('transform', 'rotate(' + Degrees + ' 35 35)');
        }

       // Process configuration changes 
       function onConfigChange(newConfig) {
           if (newConfig.ShowLabel && scope.runtimeData.labelOptions !== '') {
               if (scope.config.LabelType === 'Full' || scope.runtimeData.labelOptions.length < 2) {
                    scope.Label = scope.runtimeData.labelOptions[0].Value;
                } else {
                    scope.Label = scope.runtimeData.labelOptions[1].Value;
                }
            }
            showLabels(scope.Width, scope.Height);
            setSVGPadding();
        }

        // Process symbol resize
        function onResize(width, height) {
            showLabels(width, height);
            setSVGPadding();
        }

        // Turn off labels if symbol is to small for their display
        function showLabels(width, height) {
            var labelsDisplayed = 0;
            var labelWidth = 0;
            var defaultLabelHeight = 50;
            var compareWidth = 0;

            scope.Width = width;
            scope.Height = height;

            if (scope.config.ShowLabel) {
                labelsDisplayed++;
                labelWidth = textWidth(scope.Label);
            }
            if (scope.config.ShowTimestamp) {
                labelsDisplayed++;
                compareWidth = textWidth(scope.Timestamp);
                labelWidth = labelWidth > compareWidth ? labelWidth : compareWidth;
            }
            if (scope.config.ShowValue) {
                labelsDisplayed++;
                compareWidth = textWidth(scope.Units === undefined ? scope.Value : scope.Value.concat(scope.Units));
                labelWidth = labelWidth > compareWidth ? labelWidth : compareWidth;
            }

            if (width < labelWidth || height < labelsDisplayed * defaultLabelHeight) {
                scope.showText = false;
            } else {
                scope.showText = true;
            }
        }

        // Adjust svg top padding based on number of text items displayed
        // This ensures that the svg arrow and text items fit within the symbol boundaries
        function setSVGPadding() {
            var labelsDisplayed = 0;
            var paddingTop;

            if (scope.showText) {
                if (scope.config.ShowLabel) {
                    labelsDisplayed++;
                }
                if (scope.config.ShowTimestamp) {
                    labelsDisplayed++;
                }
                if (scope.config.ShowValue) {
                    labelsDisplayed++;
                }
            }

            switch (labelsDisplayed) {
                case 0:
                    paddingTop = "2px";
                    break;
                case 1:
                    paddingTop = "10px";
                    break;
                case 2:
                    paddingTop = "18px";
                    break;
                case 3:
                    paddingTop = "32px";
                    break;
            }
            var sampleArrow = elem.find('.sample-arrow')[0];
            sampleArrow.style.paddingTop = paddingTop;
        }

        // Calculate the text required width 
        function textWidth(textValue) {
            return textValue ? textValue.length * 7.3 : 0;
        }

        // Update label text if provided by data update
        // This could change if a new element was dropped on the symbol 
        function setLabelOptions(newLabel) {
            if (newLabel.indexOf('|') > 0) {
                var labelOptions = newLabel.split('|');
                scope.runtimeData.labelOptions = [{ Type: 'Full', Value: newLabel }, { Type: 'Partial', Value: labelOptions[labelOptions.length - 1]}];
            } else {
                scope.runtimeData.labelOptions = [{ Type: 'Full', Value: newLabel }];
            }

            if (scope.config.LabelType === 'Full' || scope.runtimeData.labelOptions.length < 2) {
                scope.Label = scope.runtimeData.labelOptions[0].Value;
            } else {
                scope.Label = scope.runtimeData.labelOptions[1].Value;
            }
        }
    };

	PV.symbolCatalog.register(definition); 
})(window.PIVisualization); 

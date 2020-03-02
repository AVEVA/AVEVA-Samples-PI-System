var symArrow;
var symbol;
var elem;
var Configuration = {
    ArrowDefaultColor: 'green',
    DataShape: 'Gauge',
    Height: 80,
    LabelColor: 'grey',
    LabelType: 'Full',
    Left: 0,
    ShowLabel: false,
    ShowTimestamp: false,
    ShowValue: false,
    Top: 0,
    ValueColor: 'white',
    ValueScale: false,
    ValueScaleSettings: {MinType: 2, MinValue: 0, MaxType: 2},
    Width: 80
}
var Data = {
    Indicator: 5.56,
    Label: 'SanLeandro|WindDirection',
    Path: 'af:\\CSAF\Davinci\Cities\SanLeandro|WindDirection', 
    Value: "20", 
    Time: "2015-09-16 16:11:12", 
    SymbolName: "Symbol0"
}
var scope = {
    runtimeData: {labelOptions: {length: 4}},
    config: Configuration
};

describe("sym-arrow", function() {

    elem = document.getElementsByClassName("symbol")[0];
    elem.find = function (className) {
        return document.getElementsByClassName(className.replace(".", ""));
    };

    it("init: show text should be true", function() {
        symbol.prototype.init(scope, elem);
        expect(scope.showText).toEqual(true);
    });

    it("getDefaultConfig: arrow default color should be green", function() {
        var config = symArrow.getDefaultConfig();
        expect(config.ArrowDefaultColor).toEqual('green');
    });

    it("onResize: show labels width should be 10", function() {
        symbol.prototype.init(scope, elem);
        symbol.prototype.onResize(10, 10);
        expect(scope.Width).toEqual(10);
    });
                        
    it("onResize: when width is 500 and height is 500 then showtext should be true", function() {
        scope.config.LabelType = 'Full';
        Configuration.ShowLabel = true;
        symbol.prototype.init(scope, elem);
        symbol.prototype.onDataUpdate(Data);
        symbol.prototype.onResize(500, 500);
        expect(scope.showText).toEqual(true);
    });
                        
    it("onResize: when width is 100 and height is 100 then showtext should be false", function() {
        scope.config.LabelType = 'Full';
        Configuration.ShowLabel = true;
        symbol.prototype.init(scope, elem);
        symbol.prototype.onDataUpdate(Data);
        symbol.prototype.onResize(100, 100);
        expect(scope.showText).toEqual(false);
    });

    it("onDataUpdate: when LabelType = Full then label should be SanLeandro|WindDirection", function() {
        scope.config.LabelType = 'Full';
        symbol.prototype.init(scope, elem);
        symbol.prototype.onDataUpdate(Data);
        expect(scope.Label).toEqual('SanLeandro|WindDirection');
    });
    
    it("onDataUpdate: when LabelType != Full then label should be WindDirection", function() {
        scope.config.LabelType = 'partial';
        symbol.prototype.init(scope, elem);
        symbol.prototype.onDataUpdate(Data);
        expect(scope.Label).toEqual('WindDirection');
    });
        
    it("onDataUpdate: when data value is 20 then scope value should be 20", function() {
        scope.config.LabelType = 'Full';
        symbol.prototype.init(scope, elem);
        Data.Value = '20';
        symbol.prototype.onDataUpdate(Data);
        expect(scope.Value).toEqual('20');
    });
            
    it("onDataUpdate: when data value is changed to 30 then scope value should be 30", function() {
        scope.config.LabelType = 'Full';
        symbol.prototype.init(scope, elem);
        Data.Value = '30';
        symbol.prototype.onDataUpdate(Data);
        expect(scope.Value).toEqual('30');
    });
                
    it("onConfigChange: when ShowLabel false then label should be blank", function() {
        Configuration.ShowLabel = false;
        symbol.prototype.init(scope, elem);
        symbol.prototype.onDataUpdate(Data);
        symbol.prototype.onResize(100, 100);
        scope.Label = '';
        symbol.prototype.onConfigChange(Configuration);
        expect(scope.Label).toEqual('');
    });
                    
    it("onConfigChange: when ShowLabel true then label should be SanLeandro|WindDirection", function() {
        scope.config.LabelType = 'Full';
        Configuration.ShowLabel = true;
        symbol.prototype.init(scope, elem);
        symbol.prototype.onDataUpdate(Data);
        symbol.prototype.onResize(100, 100);
        scope.Label = '';
        symbol.prototype.onConfigChange(Configuration);
        expect(scope.Label).toEqual('SanLeandro|WindDirection');
    });
});


#import "AshtonHTMLReader.h"
#import "AshtonIntermediate.h"

@interface AshtonHTMLReader ()
@property (nonatomic, strong) NSXMLParser *parser;
@property (nonatomic, strong) NSMutableAttributedString *output;
@property (nonatomic, strong) NSMutableArray *styleStack;
@end

@implementation AshtonHTMLReader

+ (instancetype)sharedInstance {
    return [[AshtonHTMLReader alloc] init];
}

- (NSAttributedString *)attributedStringFromHTMLString:(NSString *)htmlString {
    self.output = [[NSMutableAttributedString alloc] init];
    self.styleStack = [NSMutableArray array];
    NSMutableString *stringToParse = [NSMutableString stringWithCapacity:(htmlString.length + 13)];
    [stringToParse appendString:@"<html>"];
    [stringToParse appendString:htmlString];
    [stringToParse appendString:@"</html>"];
    self.parser = [[NSXMLParser alloc] initWithData:[stringToParse dataUsingEncoding:NSUTF8StringEncoding]];
    self.parser.delegate = self;
    [self.parser parse];
    return self.output;
}

- (NSDictionary *)attributesForStyleString:(NSString *)styleString href:(NSString *)href {
    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];

    if (href) {
        attrs[AshtonAttrLink] = href;
    }

    if (styleString) {
        NSScanner *scanner = [NSScanner scannerWithString:styleString];
        while (![scanner isAtEnd]) {
            NSString *key;
            NSString *value;
            [scanner scanCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:NULL];
            [scanner scanUpToString:@":" intoString:&key];
            [scanner scanString:@":" intoString:NULL];
            [scanner scanCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:NULL];
            [scanner scanUpToString:@";" intoString:&value];
            [scanner scanString:@";" intoString:NULL];
            [scanner scanCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:NULL];
            if ([key isEqualToString:@"text-align"]) {
                // produces: paragraph.text-align
                NSMutableDictionary *paragraphAttrs = attrs[AshtonAttrParagraph];
                if (!paragraphAttrs) paragraphAttrs = attrs[AshtonAttrParagraph] = [NSMutableDictionary dictionary];

                if ([value isEqualToString:@"left"]) paragraphAttrs[AshtonParagraphAttrTextAlignment] = AshtonParagraphAttrTextAlignmentStyleLeft;
                if ([value isEqualToString:@"right"]) paragraphAttrs[AshtonParagraphAttrTextAlignment] = AshtonParagraphAttrTextAlignmentStyleRight;
                if ([value isEqualToString:@"center"]) paragraphAttrs[AshtonParagraphAttrTextAlignment] = AshtonParagraphAttrTextAlignmentStyleCenter;
            }
            if ([key isEqualToString:AshtonAttrFont]) {
                // produces: font
                NSScanner *scanner = [NSScanner scannerWithString:value];
                BOOL traitBold = [scanner scanString:@"bold " intoString:NULL];
                BOOL traitItalic = [scanner scanString:@"italic " intoString:NULL];
                NSInteger pointSize; [scanner scanInteger:&pointSize];
                [scanner scanString:@"px " intoString:NULL];
                [scanner scanString:@"\"" intoString:NULL];
                NSString *familyName; [scanner scanUpToString:@"\"" intoString:&familyName];

                attrs[AshtonAttrFont] = @{ AshtonFontAttrTraitBold: @(traitBold), AshtonFontAttrTraitItalic: @(traitItalic), AshtonFontAttrFamilyName: familyName, AshtonFontAttrPointSize: @(pointSize), AshtonFontAttrFeatures: @[] };
            }
            if ([key isEqualToString:@"-cocoa-font-features"]) {
                // We expect -cocoa-font-features to only happen after font
                NSMutableArray *features = [NSMutableArray array];

                NSMutableDictionary *font = [attrs[AshtonAttrFont] mutableCopy];
                for (NSString *feature in [value componentsSeparatedByString:@" "]) {
                    NSArray *values = [feature componentsSeparatedByString:@"/"];
                    [features addObject:@[@([values[0] intValue]), @([values[1] intValue])]];
                }

                font[AshtonFontAttrFeatures] = features;
                attrs[AshtonAttrFont] = font;
            }

            if ([key isEqualToString:@"-cocoa-underline"]) {
                // produces: underline
                if ([value isEqualToString:@"single"]) attrs[AshtonAttrUnderline] = AshtonUnderlineStyleSingle;
                if ([value isEqualToString:@"thick"]) attrs[AshtonAttrUnderline] = AshtonUnderlineStyleThick;
                if ([value isEqualToString:@"double"]) attrs[AshtonAttrUnderline] = AshtonUnderlineStyleDouble;
            }
            if ([key isEqualToString:@"-cocoa-underline-color"]) {
                // produces: underlineColor
                attrs[AshtonAttrUnderlineColor] = [self colorForCSS:value];
            }
            if ([key isEqualToString:AshtonAttrColor]) {
                // produces: color
                attrs[AshtonAttrColor] = [self colorForCSS:value];
            }
            if ([key isEqualToString:@"-cocoa-strikethrough"]) {
                // produces: strikethrough
                if ([value isEqualToString:@"single"]) attrs[AshtonAttrStrikethrough] = AshtonStrikethroughStyleSingle;
                if ([value isEqualToString:@"thick"]) attrs[AshtonAttrStrikethrough] = AshtonStrikethroughStyleThick;
                if ([value isEqualToString:@"double"]) attrs[AshtonAttrStrikethrough] = AshtonStrikethroughStyleDouble;
            }
            if ([key isEqualToString:@"-cocoa-strikethrough-color"]) {
                // produces: strikethroughColor
                attrs[AshtonAttrStrikethroughColor] = [self colorForCSS:value];
            }
        }
    }

    return attrs;
}

- (NSDictionary *)currentAttributes {
    NSMutableDictionary *mergedAttrs = [NSMutableDictionary dictionary];
    for (NSDictionary *attrs in self.styleStack) {
        [mergedAttrs addEntriesFromDictionary:attrs];
    }
    return mergedAttrs;
}

- (void)parserDidStartDocument:(NSXMLParser *)parser {
    [self.output beginEditing];
}

- (void)parserDidEndDocument:(NSXMLParser *)parser {
    [self.output endEditing];
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict {
    if ([elementName isEqualToString:@"html"]) return;
    if (self.output.length > 0) {
        if ([elementName isEqualToString:@"p"]) [self.output appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
    }
    [self.styleStack addObject:[self attributesForStyleString:attributeDict[@"style"] href:attributeDict[@"href"]]];
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
    if ([elementName isEqualToString:@"html"]) return;
    [self.styleStack removeLastObject];
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError {
    NSLog(@"error %@", parseError);
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    NSMutableAttributedString *fragment = [[NSMutableAttributedString alloc] initWithString:string attributes:[self currentAttributes]];
    [self.output appendAttributedString:fragment];
}

- (id)colorForCSS:(NSString *)css {
  NSScanner *scanner = [NSScanner scannerWithString:css];
  [scanner scanString:@"rgba(" intoString:NULL];
  int red; [scanner scanInt:&red];
  [scanner scanString:@", " intoString:NULL];
  int green; [scanner scanInt:&green];
  [scanner scanString:@", " intoString:NULL];
  int blue; [scanner scanInt:&blue];
  [scanner scanString:@", " intoString:NULL];
  float alpha; [scanner scanFloat:&alpha];
 
  return @[ @((float)red / 255), @((float)green / 255), @((float)blue / 255), @(alpha) ];
}
@end

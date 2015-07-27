//
//  Planck.m
//  planck
//
//  Created by Mike Fikes on 7/16/15.
//  Copyright (c) 2015 FikesFarm. All rights reserved.
//

#include <stdio.h>

#import "Planck.h"
#import "ABYContextManager.h"
#import "ABYServer.h"

@implementation Planck

-(void)runEval:(NSString*)evalArg srcPath:(NSString*)srcPath outPath:(NSString*)outPath {
   
    if (!evalArg && isatty(fileno(stdin))) {
        printf("cljs.user=> ");
        fflush(stdout);
    }
    
    NSURL* outURL = [NSURL URLWithString:@"out"];
    
    if (outPath) {
        outURL = [NSURL URLWithString:outPath];
    }
    
    NSFileManager* fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:outURL.path isDirectory:nil]) {
        NSLog(@"ClojureScript compiler output directory not found at \"%@\".", outURL.path);
        NSLog(@"(Current working directory is \"%@\")", [fm currentDirectoryPath]);
        exit(1);
    }
    
    ABYContextManager* contextManager = [[ABYContextManager alloc] initWithContext:JSGlobalContextCreate(NULL)
                                                           compilerOutputDirectory:outURL];
    [contextManager setUpConsoleLog];
    [contextManager setupGlobalContext];
    [contextManager setUpAmblyImportScript];
   
    NSString* mainJsFilePath = [[outURL URLByAppendingPathComponent:@"main" isDirectory:NO]
                                URLByAppendingPathExtension:@"js"].path;
    
    NSURL* googDirectory = [outURL URLByAppendingPathComponent:@"goog"];
    
    [contextManager bootstrapWithDepsFilePath:mainJsFilePath
                                 googBasePath:[[googDirectory URLByAppendingPathComponent:@"base" isDirectory:NO] URLByAppendingPathExtension:@"js"].path];
    
    JSContext* context = [JSContext contextWithJSGlobalContextRef:contextManager.context];
    
    [self requireAppNamespaces:context];
    
#ifdef DEBUG
    BOOL debugBuild = YES;
#else
    BOOL debugBuild = NO;
#endif
    
    // TODO look into this. Without it thngs won't work.
    [context evaluateScript:@"var window = global;"];
    
    JSValue* initAppEnvFn = [self getValue:@"init-app-env" inNamespace:@"planck.core" fromContext:context];
    [initAppEnvFn callWithArguments:@[@{@"debug-build": @(debugBuild),
                                        @"user-interface-idiom": @"iPad"}]];
    
    JSValue* readEvalPrintFn = [self getValue:@"read-eval-print" inNamespace:@"planck.core" fromContext:context];
    NSAssert(!readEvalPrintFn.isUndefined, @"Could not find the read-eval-print function");
    
    JSValue* printPromptFn = [self getValue:@"print-prompt" inNamespace:@"planck.core" fromContext:context];
    NSAssert(!printPromptFn.isUndefined, @"Could not find the print-prompt function");
    
    JSValue* isReadableFn = [self getValue:@"is-readable?" inNamespace:@"planck.core" fromContext:context];
    NSAssert(!isReadableFn.isUndefined, @"Could not find the is-readable? function");
    
    context[@"PLANCK_READ_FILE"] = ^(NSString *file) {
        return [NSString stringWithContentsOfFile:file
                                         encoding:NSUTF8StringEncoding error:nil];
    };
    
    context[@"PLANCK_WRITE_FILE"] = ^(NSString *file, NSString* content) {
        [content writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return @"";
    };
    
    context[@"PLANCK_PRINT_FN"] = ^(NSString *message) {
        // supressing
    };
    
    [context evaluateScript:@"cljs.core.set_print_fn_BANG_.call(null,PLANCK_PRINT_FN);"];
    [context evaluateScript:@"cljs.core.set_print_err_fn_BANG_.call(null,PLANCK_PRINT_FN);"];
    

    context[@"PLANCK_PRINT_FN"] = ^(NSString *message) {
        if (!evalArg || ![message isEqualToString:@"nil"]) {
            printf("%s", message.cString);
        }
    };
    
    [context evaluateScript:@"cljs.core.set_print_fn_BANG_.call(null,PLANCK_PRINT_FN);"];

    BOOL runAmblyReplServer = NO;
    if (runAmblyReplServer) {
        ABYServer* replServer = [[ABYServer alloc] initWithContext:contextManager.context
                                           compilerOutputDirectory:outURL];
        [replServer startListening];
        
        BOOL shouldKeepRunning = YES;
        NSRunLoop *theRL = [NSRunLoop currentRunLoop];
        while (shouldKeepRunning && [theRL runMode:NSDefaultRunLoopMode beforeDate:[NSDate     distantFuture]]);
        
    } else {
        if (evalArg) {
            [readEvalPrintFn callWithArguments:@[evalArg]];
        } else {
            NSString* input = nil;
            for (;;) {
                NSString* inputLine = [self getInput];
                
                if (input == nil) {
                    input = inputLine;
                } else {
                    input = [NSString stringWithFormat:@"%@\n%@", input, inputLine];
                }
                if ([input isEqualToString:@":cljs/quit"] || [input isEqualToString:@""]) {
                    break;
                }
                BOOL isReadable = [isReadableFn callWithArguments:@[input]].toBool;
                if (isReadable) {
                    [readEvalPrintFn callWithArguments:@[input]];
                    input = nil;
                    if (!evalArg && isatty(fileno(stdin))) {
                        [printPromptFn callWithArguments:@[]];
                        fflush(stdout);
                    }
                }
            }
        }
    }

}

-(NSString *) getInput
{
    NSFileHandle *input = [NSFileHandle fileHandleWithStandardInput];
    NSData *inputData = [input availableData];
    NSString *inputString = [[NSString alloc] initWithData: inputData encoding:NSUTF8StringEncoding];
    inputString = [inputString stringByTrimmingCharactersInSet: [NSCharacterSet newlineCharacterSet]];
    
    return inputString;
}

-(void)requireAppNamespaces:(JSContext*)context
{
    [context evaluateScript:[NSString stringWithFormat:@"goog.require('%@');", [self munge:@"planck.core"]]];
}

- (JSValue*)getValue:(NSString*)name inNamespace:(NSString*)namespace fromContext:(JSContext*)context
{
    JSValue* namespaceValue = nil;
    for (NSString* namespaceElement in [namespace componentsSeparatedByString: @"."]) {
        if (namespaceValue) {
            namespaceValue = namespaceValue[[self munge:namespaceElement]];
        } else {
            namespaceValue = context[[self munge:namespaceElement]];
        }
    }
    
    return namespaceValue[[self munge:name]];
}

-(NSString*)munge:(NSString*)s
{
    return [[[s stringByReplacingOccurrencesOfString:@"-" withString:@"_"]
             stringByReplacingOccurrencesOfString:@"!" withString:@"_BANG_"]
            stringByReplacingOccurrencesOfString:@"?" withString:@"_QMARK_"];
}

@end

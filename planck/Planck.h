//
//  Planck.h
//  planck
//
//  Created by Mike Fikes on 7/16/15.
//  Copyright (c) 2015 FikesFarm. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Planck : NSObject

-(void)runEval:(NSString*)evalArg srcPath:(NSString*)srcPath outPath:(NSString*)outPath mainNsName:(NSString*)mainNsName args:(NSArray*)args;

@end

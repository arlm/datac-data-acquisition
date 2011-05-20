// -*- Mode: ObjC -*-
//
// Copyright (C) 2011, Brad Howes. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SampleProcessorProtocol.h"

@class LowPassFilter;

enum EdgeKind {
    kEdgeKindUnknown,
    kEdgeKindRising,
    kEdgeKindFalling
};

@interface AboveLevelCounter : NSObject<SampleProcessorProtocol> {
@private
    Float32 level;
    LowPassFilter* lowPassFilter;
    EdgeKind currentEdge;
    UInt32 counter;
}

@property (nonatomic, assign) Float32 level;
@property (nonatomic, retain) LowPassFilter* lowPassFilter;
@property (nonatomic, readonly) EdgeKind currentEdge;
@property (nonatomic, readonly) UInt32 counter;

+ (AboveLevelCounter*)createWithLevel:(Float32)level;

- (id)initWithLevel:(Float32)level;

- (UInt32)counterAndReset;

- (void)reset;

@end

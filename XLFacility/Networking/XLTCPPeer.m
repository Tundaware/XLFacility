/*
 Copyright (c) 2014, Pierre-Olivier Latour
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * The name of Pierre-Olivier Latour may not be used to endorse
 or promote products derived from this software without specific
 prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL PIERRE-OLIVIER LATOUR BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#if !__has_feature(objc_arc)
#error XLFacility requires ARC
#endif

#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

#import "XLTCPPeer.h"
#import "XLPrivate.h"

@interface XLTCPPeerConnection ()
@property(nonatomic, assign) XLTCPPeer* peer;
@end

@implementation XLTCPPeerConnection

- (void)didClose {
  [super didClose];
  
  [_peer didCloseConnection:self];
  _peer = nil;
}

@end

@interface XLTCPPeer () {
@private
  dispatch_queue_t _lockQueue;
  dispatch_group_t _syncGroup;
  NSMutableSet* _connections;
#if TARGET_OS_IPHONE
  UIBackgroundTaskIdentifier _backgroundTask;
  BOOL _restart;
#endif
}
@end

@implementation XLTCPPeer

- (id)init {
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (instancetype)initWithConnectionClass:(Class)connectionClass {
  XLOG_DEBUG_CHECK([connectionClass isSubclassOfClass:[XLTCPPeerConnection class]]);
  if ((self = [super init])) {
    _connectionClass = connectionClass;
    
    _lockQueue = dispatch_queue_create(XLDISPATCH_QUEUE_LABEL, DISPATCH_QUEUE_SERIAL);
    _syncGroup = dispatch_group_create();
    _connections = [[NSMutableSet alloc] init];
#if TARGET_OS_IPHONE
    _backgroundTask = UIBackgroundTaskInvalid;
#endif
  }
  return self;
}

#if !OS_OBJECT_USE_OBJC_RETAIN_RELEASE

- (void)dealloc {
  dispatch_release(_syncGroup);
  dispatch_release(_lockQueue);
}

#endif

- (NSSet*)connections {
  __block NSSet* connections;
  dispatch_sync(_lockQueue, ^{
    connections = [_connections copy];
  });
  return connections;
}

- (BOOL)start {
  XLOG_CHECK(!_running);
  
  if (![self willStart]) {
    return NO;
  }
  
#if TARGET_OS_IPHONE
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_didEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_willEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
  if (!_suspendInBackground) {
    _backgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
      [self stop];
      _restart = YES;
      
      [[UIApplication sharedApplication] endBackgroundTask:_backgroundTask];
      _backgroundTask = UIBackgroundTaskInvalid;
    }];
  }
  _restart = NO;
#endif
  
  _running = YES;
  return YES;
}

#if TARGET_OS_IPHONE

- (void)_didEnterBackground:(NSNotification*)notification {
  if (_running && _suspendInBackground) {
    [self stop];
    _restart = YES;
  }
}

- (void)_willEnterForeground:(NSNotification*)notification {
  if (_restart) {
    [self start];  // Not much we can do on failure
  }
}

#endif

- (void)stop {
  XLOG_CHECK(_running);
  
#if TARGET_OS_IPHONE
  if (_backgroundTask != UIBackgroundTaskInvalid) {
    [[UIApplication sharedApplication] endBackgroundTask:_backgroundTask];
    _backgroundTask = UIBackgroundTaskInvalid;
  }
  [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
#endif
  
  [self didStop];
  
  NSSet* connections = self.connections;
  for (XLTCPPeerConnection* connection in connections) {  // No need to use "_lockQueue" since no new connections can be created anymore and it would deadlock with -didCloseConnection:
    [connection close];
  }
  dispatch_group_wait(_syncGroup, DISPATCH_TIME_FOREVER);  // Wait until all connections are closed
  
  _running = NO;
}

@end

@implementation XLTCPPeer (Subclassing)

- (dispatch_queue_t)lockQueue {
  return _lockQueue;
}

- (BOOL)willStart {
  return YES;
}

- (void)didStop {
  ;
}

- (void)willOpenConnection:(XLTCPPeerConnection*)connection {
  XLOG_DEBUG(@"%@ did connect to peer at \"%@\" (%i)", [self class], connection.remoteIPAddress, (int)connection.remotePort);
  connection.peer = self;
  dispatch_sync(_lockQueue, ^{
    dispatch_group_enter(_syncGroup);
    [_connections addObject:connection];
  });
  [connection open];
}

- (void)didCloseConnection:(XLTCPPeerConnection*)connection {
  dispatch_sync(_lockQueue, ^{
    if ([_connections containsObject:connection]) {
      [_connections removeObject:connection];
      dispatch_group_leave(_syncGroup);
    }
  });
  XLOG_DEBUG(@"%@ did disconnect from peer at \"%@\" (%i)", [self class], connection.remoteIPAddress, (int)connection.remotePort);
}

@end

@implementation XLTCPPeer (Extensions)

- (void)enumerateConnectionsUsingBlock:(void (^)(XLTCPPeerConnection* connection, BOOL* stop))block {
  dispatch_sync(_lockQueue, ^{
    BOOL stop = NO;
    for (XLTCPPeerConnection* connection in _connections) {
      block(connection, &stop);
      if (stop) {
        break;
      }
    }
  });
}

@end

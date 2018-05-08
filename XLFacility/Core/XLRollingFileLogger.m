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

#import "XLRollingFileLogger.h"
#import "XLFileLogger.h"

#import <sys/stat.h>

#define kXLRollingFileLoggerDefaultMaxFileSize      1024 * 1024 * 1 // 1 MB
#define kXLRollingFileLoggerDefaultMaxNumberOfFiles 10

@interface XLRollingFileLogger ()

@property (nonatomic, strong) XLFileLogger *backingLogger;
@property (nonatomic, strong) XLFileLogger *rolledLogger;

@property (nonatomic, copy) NSArray<XLRollingFileLoggerFileInfo *> *fileInfos;

@property (nonatomic, copy) NSString *directoryPath;
@property (nonatomic, strong) dispatch_queue_t purgeQueue;
@property (nonatomic) BOOL isRolling;

@end

@interface XLRollingFileLoggerFileInfo ()

@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, strong) NSDate *creationDate;
@property (nonatomic) long long size;

@end

@implementation XLRollingFileLogger

- (instancetype)initWithDirectoryPath:(NSString * _Nonnull)path create:(BOOL)create {
  if ((self = [super init])) {
    _directoryPath = path;

    if (create) {
      [self ensureDirectoryExists:path];
    }

    _purgeQueue = dispatch_queue_create([[NSString stringWithFormat:@"%@.purging", self.class]
                                         cStringUsingEncoding:NSUTF8StringEncoding],
                                        DISPATCH_QUEUE_SERIAL);

    _maxFileSize = kXLRollingFileLoggerDefaultMaxFileSize;
    _maxNumberOfFiles = kXLRollingFileLoggerDefaultMaxNumberOfFiles;

    [self purgeOldFiles];

    _backingLogger = [self generateLoggerWithLogFilePath];
  }
  return self;
}

- (void)setFormat:(NSString *)format {
  [super setFormat:format];

  self.backingLogger.format = format;
}

- (BOOL)open {
  BOOL result = [self.backingLogger open];
  [self populateFileInfos];
  return result;
}

- (void)close {
  [self.backingLogger close];
  [self.rolledLogger close];
}

- (void)logRecord:(XLLogRecord *)record {
  if (!self.isRolling && [self shouldRoll]) {
    [self roll];
  }
  [self.backingLogger logRecord:record];
}

#pragma mark - Overridable

- (NSString *)generateNextLogFilename {
  return [NSString stringWithFormat:@"%@.log", @([NSDate timeIntervalSinceReferenceDate])];
}

- (NSString *)generateNextLogFilePath {
  return [self.directoryPath stringByAppendingPathComponent:[self generateNextLogFilename]];
}

- (BOOL)shouldRoll {
  if (self.isRolling) {
    return NO;
  }

  struct stat statinfo;
  if (stat([self.backingLogger.filePath fileSystemRepresentation], &statinfo)) {
    // Failed to retrieve stat info about the file
    return NO;
  }
  return statinfo.st_size > self.maxFileSize;
}

#pragma mark - Private
- (void)ensureDirectoryExists:(NSString *)path {
  NSFileManager *fm = [NSFileManager defaultManager];
  BOOL isDirectory = NO;
  if (!([fm fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory)) {
    NSError *error = nil;
    if (![fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]) {
      // TODO: Deal with error
    }
  }
}

- (XLFileLogger *)generateLoggerWithLogFilePath {
  XLFileLogger *logger = [[XLFileLogger alloc] initWithFilePath:[self generateNextLogFilePath] append:YES];
  logger.format = self.format;
  return logger;
}

- (void)populateFileInfos {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSMutableArray *fileInfos = NSMutableArray.new;
  NSError *error = nil;

  NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:self.directoryPath error:&error];
  if (error) {
    // TODO: Deal with error
  } else {
    for (NSString *filename in files) {
      [fileInfos addObject:[XLRollingFileLoggerFileInfo fileInfoWithPath:[self.directoryPath stringByAppendingPathComponent:filename]]];
    }
  }
  self.fileInfos = [fileInfos sortedArrayUsingComparator:^NSComparisonResult(XLRollingFileLoggerFileInfo *obj1, XLRollingFileLoggerFileInfo *obj2) {
    return [obj1.creationDate compare:obj2.creationDate];
  }];
}

- (void)roll {
  self.rolledLogger = self.backingLogger;
  self.backingLogger = [self generateLoggerWithLogFilePath];

  if (self.rolledLogger.isOpen) {
    [self open];
    [self.rolledLogger close];
  }

  dispatch_async(self.purgeQueue, ^{
    [self purgeOldFiles];
  });
}

- (void)purgeOldFiles {
  [self populateFileInfos];

  if (self.fileInfos.count <= self.maxNumberOfFiles) {
    return;
  }
  NSRange rangeToPurge = NSMakeRange(0, (self.fileInfos.count - self.maxNumberOfFiles));
  NSIndexSet *indexesToPurge = [NSIndexSet indexSetWithIndexesInRange:rangeToPurge];
  NSArray<XLRollingFileLoggerFileInfo *> *fileInfosToPurge = [self.fileInfos objectsAtIndexes:indexesToPurge];
  NSFileManager *fm = [NSFileManager defaultManager];
  for (XLRollingFileLoggerFileInfo *fileInfo in fileInfosToPurge) {
    NSError *error = nil;
    if (![fm removeItemAtPath:fileInfo.filePath error:&error]) {
      // TODO: Deal with error
    }
  }
  NSMutableArray<XLRollingFileLoggerFileInfo *> *workingFileInfos = [self.fileInfos mutableCopy];
  [workingFileInfos removeObjectsInArray:fileInfosToPurge];
  self.fileInfos = workingFileInfos;
}

@end

@implementation XLRollingFileLoggerFileInfo

+ (instancetype)fileInfoWithPath:(NSString *)path {
  XLRollingFileLoggerFileInfo *info = [[self alloc] init];
  info.filePath = path;

  NSFileManager *fm = [NSFileManager defaultManager];
  NSError *error = nil;
  NSDictionary *attributes = [fm attributesOfItemAtPath:path error:&error];
  if (error) {
    // TODO: Deal with error
  } else {
    info.size = attributes.fileSize;
    info.creationDate = attributes.fileCreationDate;
  }

  return info;
}

@end

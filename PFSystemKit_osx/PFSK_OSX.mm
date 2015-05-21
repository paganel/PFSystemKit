//
//  PFSK_OSX.m
//  PFSystemKit
//
//  Created by Perceval FARAMAZ on 19/04/15.
//  Copyright (c) 2015 Perceval FARAMAZ. All rights reserved.
//

#import <sys/sysctl.h>
#import <CoreFoundation/CoreFoundation.h>
#import <string>
#import <vector>
#import "PFSKHelper.h"
#import "PFSK_OSX.h"
/*#import "PFSK_OSX+CPU.h"
#import "PFSK_OSX+GPU.h"
#import "PFSK_OSX+RAM.h"
#import "PFSK_OSX+GPU.h"*/
#import "PFSK_Common+Machine.h"

@interface PFSK_Common()
//+(PFSystemKitError) sysctlStringForKey:(char*)key intoChar:(std::string&)answerChar;
//+(PFSystemKitError) sysctlFloatForKey:(char*)key intoFloat:(CGFloat&)answerFloat;
@end

@implementation PFSystemKit
#pragma mark - Singleton pattern
/**
 * PFSystemKit singleton instance retrieval method
 */
+(instancetype) investigate {
	static PFSystemKit* sharedInstance;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedInstance = [[self alloc] init];
	});
	return sharedInstance;
}


#pragma mark - Class methods (actual core code)

-(BOOL) refreshGroup:(PFSystemKitGroup)group {
	kern_return_t result;
	switch (group) {
		case PFSKGroupPlatformExpertDevice: {
			if (!firstRunDoneForExpertDevice) {
				pexEntry = IOServiceGetMatchingService(masterPort, IOServiceMatching("IOPlatformExpertDevice"));
				if (pexEntry == 0) {
					_error = PFSKReturnComponentUnavailable;
					return false;
				}
				firstRunDoneForExpertDevice = 1;
			}
			CFMutableDictionaryRef pexProps = NULL;
			result = IORegistryEntryCreateCFProperties(pexEntry, &pexProps, NULL, 0);
			if (result!=kIOReturnSuccess) {
				_error = PFSKReturnIOKitCFFailure;
				_extError = result;
				return false;
			} else {
				platformExpertRawDict = (__bridge NSDictionary*)pexProps;
				CFRelease(pexProps);
				[self setValue:[platformExpertRawDict objectForKey:@"model"] forKey:@"model"];
				[self setValue:[platformExpertRawDict objectForKey:@"board-id"] forKey:@"boardID"];
				[self setValue:[platformExpertRawDict objectForKey:@kIOPlatformSerialNumberKey] forKey:@"serial"];
				[self setValue:[platformExpertRawDict objectForKey:@kIOPlatformUUIDKey] forKey:@"platformID"];
			}
			break;
		}
		case PFSKGroupROM: {
			if (!firstRunDoneForROM) {
				romEntry = IORegistryEntryFromPath(masterPort, "IODeviceTree:/rom@0");
				if (romEntry == 0) {
					_error = PFSKReturnComponentUnavailable;
					return false;
				}
				firstRunDoneForROM = 1;
			}
			CFMutableDictionaryRef romProps = NULL;
			result = IORegistryEntryCreateCFProperties(romEntry, &romProps, NULL, 0);
			if (result!=kIOReturnSuccess) {
				_error = PFSKReturnIOKitCFFailure;
				_extError = result;
				return false;
			} else {
				romRawDict = (__bridge NSDictionary*)romProps;
				CFRelease(romProps);
				val4Key("romVersion", [romRawDict objectForKey:@"version"]);
				NSString* dateStr = [NSString.alloc initWithData:[romRawDict objectForKey:@"release-date"] encoding:NSUTF8StringEncoding];
				NSDateComponents* romDateComps = [NSDateComponents.alloc init];
				NSArray* romDateStrSplitted = [dateStr componentsSeparatedByString:@"/"];
				[romDateComps setMonth:[[romDateStrSplitted objectAtIndex:0] integerValue]];
				[romDateComps setDay:[[romDateStrSplitted objectAtIndex:1] integerValue]];
				[romDateComps setYear:(2000+[[romDateStrSplitted objectAtIndex:2] integerValue])];
				val4Key("romReleaseDate", [[NSCalendar currentCalendar] dateFromComponents:romDateComps]);
			}
			break;
		}
		case PFSKGroupSMC: { //to tweak SMC values, use SMCWrapper by @fmorrow
			if (!firstRunDoneForSMC) {
				smcEntry = IOServiceGetMatchingService(masterPort, IOServiceMatching("AppleSMC"));
				if (smcEntry == 0) {
					_error = PFSKReturnComponentUnavailable;
					return false;
				}
				firstRunDoneForSMC = 1;
			}
			CFMutableDictionaryRef smcProps = NULL;
			result = IORegistryEntryCreateCFProperties(smcEntry, &smcProps, NULL, 0);
			if (result!=kIOReturnSuccess) {
				_error = PFSKReturnIOKitCFFailure;
				_extError = result;
				return false;
			} else {
				smcRawDict = (__bridge NSDictionary*)smcProps;
				CFRelease(smcProps);
				val4Key("smcVersion",   [smcRawDict objectForKey:@"smc-version"]);
				val4Key("sleepCause",   [smcRawDict objectForKey:@"SleepCause"]);
				val4Key("shutdownCause",[smcRawDict objectForKey:@"ShutdownCause"]);
			}
			break;
		}
		case PFSKGroupBattery: { //to get more informations or to subscribe for events about power sources, use the IOPowerSources API
			if (!firstRunDoneForBattery) {
				batEntry = IOServiceGetMatchingService(masterPort, IOServiceMatching("IOPMPowerSource"));
				if (batEntry == 0) {
					_error = PFSKReturnComponentUnavailable;
					return false;
				}
			}
			CFMutableDictionaryRef	batProps = NULL;
			result = IORegistryEntryCreateCFProperties(batEntry, &batProps, NULL, 0);
			if (result!=kIOReturnSuccess) {
				_error = PFSKReturnIOKitCFFailure;
				_extError = result;
				return false;
			} else {
				batteryRawDict = (__bridge_transfer NSDictionary*)batProps;
				NSMutableDictionary* temp = [NSMutableDictionary.alloc init];
				if (!firstRunDoneForBattery) { //static keys
					//[temp setObject:[batteryRawDict objectForKey:@"DesignCapacity"] forKey:@"DesignedCapacity"];
					[temp setObject:[batteryRawDict objectForKey:@"DesignCycleCount9C"] forKey:@"DesignedCycleCount"];
					[temp setObject:[batteryRawDict objectForKey:@"BatterySerialNumber"] forKey:@"Serial"];
					[temp setObject:[batteryRawDict objectForKey:@"DeviceName"] forKey:@"Model"];
					[temp setObject:[batteryRawDict objectForKey:@"Manufacturer"] forKey:@"Manufacturer"];
					unsigned int manufactureDateAsInt = [[batteryRawDict objectForKey:@"ManufactureDate"] intValue];
					NSDateComponents* manufactureDateComponents = [[NSDateComponents alloc]init];
					manufactureDateComponents.year = (manufactureDateAsInt >> 9) + 1980;
					manufactureDateComponents.month = (manufactureDateAsInt >> 5) & 0xF;
					manufactureDateComponents.day = manufactureDateAsInt & 0x1F;
					[temp setObject:[[NSCalendar currentCalendar] dateFromComponents:manufactureDateComponents] forKey:@"ManufactureDate"];
					firstRunDoneForBattery = 1;
				}
				[temp setObject:[batteryRawDict objectForKey:@"BatteryInstalled"] forKey:@"isPresent"];
				[temp setObject:[batteryRawDict objectForKey:@"FullyCharged"] forKey:@"isFull"];
				[temp setObject:[batteryRawDict objectForKey:@"IsCharging"] forKey:@"isCharging"];
				[temp setObject:[batteryRawDict objectForKey:@"ExternalConnected"] forKey:@"isACConnected"];
				[temp setObject:[batteryRawDict objectForKey:@"Amperage"] forKey:@"Amperage"];
				[temp setObject:[batteryRawDict objectForKey:@"CurrentCapacity"] forKey:@"CurrentCapacity"];
				[temp setObject:[batteryRawDict objectForKey:@"MaxCapacity"] forKey:@"MaxCapacity"];
				[temp setObject:[batteryRawDict objectForKey:@"Voltage"] forKey:@"Voltage"];
				[temp setObject:[batteryRawDict objectForKey:@"CycleCount"] forKey:@"CycleCount"];
				[temp setObject:@(([[batteryRawDict objectForKey:@"MaxCapacity"] intValue] / [[batteryRawDict objectForKey:@"DesignCapacity"] intValue])*100) forKey:@"Health"]; //percentage
				[temp setObject:@([[batteryRawDict objectForKey:@"Temperature"] doubleValue] / 100) forKey:@"Temperature"];
				/*to be checked*/[temp setObject:@([[batteryRawDict objectForKey:@"Amperage"] doubleValue] / 1000 * [[batteryRawDict objectForKey:@"Voltage"] doubleValue] / 1000) forKey:@"Power"];
				NSDateComponents* differenceDate = [[NSCalendar currentCalendar] components:NSCalendarUnitDay
												fromDate:[temp objectForKey:@"ManufactureDate"]
												  toDate:[NSDate date]
												 options:0];
				[temp setObject:@([differenceDate day]) forKey:@"Age"];
				batteryReport = [temp copy];
			}
			break;
		}
		case PFSKGroupTerminator: { //just in case
			break;//return U MAD BRO
		}
		default: {
			break;
		}
	}
	_error = PFSKReturnSuccess;
	return true;
}

#pragma mark - Getters
@synthesize family;
@synthesize familyString;
@synthesize version;
@synthesize versionString;
@synthesize endianness;
@synthesize endiannessString;
@synthesize model;
@synthesize serial;

@synthesize boardID;
@synthesize platformID;
@synthesize ramSize;
@synthesize ramStats;
@synthesize cpuReport;
@synthesize romReleaseDate;
@synthesize romVersion;
@synthesize batteryReport;


#pragma mark - NSObject std methods

-(void) finalize { //cleanup everything
	IOObjectRelease(nvrEntry);
	IOObjectRelease(pexEntry);
	IOObjectRelease(smcEntry);
	IOObjectRelease(romEntry);
	[super finalize];
	return;
}

-(void) dealloc {
}

-(instancetype) init {
	if (!(self = [super init])) {
		return nil;
	}
	_writeLockState = PFSKLockStateLocked;
	_error = PFSKReturnUnknown;
	_extError = 0;
	kern_return_t IOresult;
	IOresult = IOMasterPort(bootstrap_port, &masterPort);
	if (IOresult!=kIOReturnSuccess) {
		_error = PFSKReturnNoMasterPort;
		_extError = IOresult;
		return nil;
	}
	return self;
}
@end
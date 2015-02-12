//
//  BluetoothManager.swift
//  BTCmdPeri
//
//  Created by Jay Tucker on 1/14/15.
//  Copyright (c) 2015 Imprivata. All rights reserved.
//

import Foundation
import CoreBluetooth

class BluetoothManager: NSObject {
    
    let provisioningServiceUUID = CBUUID(string: "193DB24F-E42E-49D2-9A70-6A5616863A9D")
    let commandCharacteristicUUID = CBUUID(string: "43CDD5AB-3EF6-496A-A4CC-9933F5ADAF68")
    let responseCharacteristicUUID = CBUUID(string: "F1A9A759-C922-4219-B62C-1A14F62DE0A4")
    
    private let peripheralManager: CBPeripheralManager!
    private var service: CBMutableService!
    var responseCharacteristic: CBMutableCharacteristic!
    private var isPoweredOn = false
    
    // See:
    // http://stackoverflow.com/questions/24218581/need-self-to-set-all-constants-of-a-swift-class-in-init
    // http://stackoverflow.com/questions/24441254/how-to-pass-self-to-initializer-during-initialization-of-an-object-in-swift
    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate:self, queue:nil)
    }
    
    private func startService() {
        println("startService")
        peripheralManager.stopAdvertising()
        peripheralManager.removeAllServices()
        let service = CBMutableService(type: provisioningServiceUUID, primary: true)
        let commandCharacteristic = CBMutableCharacteristic(
            type: commandCharacteristicUUID,
            properties: CBCharacteristicProperties.Write,
            value: nil,
            permissions: CBAttributePermissions.Writeable)
        responseCharacteristic = CBMutableCharacteristic(
            type: responseCharacteristicUUID,
            properties: CBCharacteristicProperties.Notify,
            value: nil,
            permissions: CBAttributePermissions.Readable)
        service.characteristics = [commandCharacteristic, responseCharacteristic]
        peripheralManager.addService(service)
    }
    
    private func startAdvertising() {
        println("startAdvertising")
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [provisioningServiceUUID]])
    }
    
    private func nameFromUUID(uuid: CBUUID) -> String {
        switch uuid {
        case provisioningServiceUUID: return "provisioningService"
        case commandCharacteristicUUID: return "commandCharacteristic"
        case responseCharacteristicUUID: return "responseCharacteristic"
        default: return "unknown"
        }
    }
    
}

extension BluetoothManager: CBPeripheralManagerDelegate {
    
    func peripheralManagerDidUpdateState(peripheralManager: CBPeripheralManager!) {
        var caseString: String!
        switch peripheralManager.state {
        case .Unknown:
            caseString = "Unknown"
        case .Resetting:
            caseString = "Resetting"
        case .Unsupported:
            caseString = "Unsupported"
        case .Unauthorized:
            caseString = "Unauthorized"
        case .PoweredOff:
            caseString = "PoweredOff"
        case .PoweredOn:
            caseString = "PoweredOn"
        default:
            caseString = "WTF"
        }
        println("peripheralManagerDidUpdateState \(caseString)")
        isPoweredOn = (peripheralManager.state == .PoweredOn)
        if isPoweredOn {
            startService()
        }
    }
    
    func peripheralManager(peripheral: CBPeripheralManager!, didAddService service: CBService!, error: NSError!) {
        var message = "peripheralManager didAddService \(nameFromUUID(service.UUID)) \(service.UUID) "
        if error == nil {
            message += "ok"
        } else {
            message = "error " + error.localizedDescription
        }
        println(message)
        startAdvertising()
    }
    
    func peripheralManagerDidStartAdvertising(peripheral: CBPeripheralManager!, error: NSError!) {
        var message = "peripheralManagerDidStartAdvertising "
        if error == nil {
            message += "ok"
        } else {
            message = "error " + error.localizedDescription
        }
        println(message)
    }
    
    func peripheralManager(peripheral: CBPeripheralManager!, central: CBCentral!, didSubscribeToCharacteristic characteristic: CBCharacteristic!) {
        let name = nameFromUUID(characteristic.UUID)
        println("peripheralManager didSubscribeToCharacteristic \(name)")
    }
    
    func peripheralManager(peripheral: CBPeripheralManager!, didReceiveWriteRequests requests: [AnyObject]!) {
        println("peripheralManager didReceiveWriteRequests \(requests.count)")
        if requests.count == 0 {
            return
        }
        let request = requests[0] as CBATTRequest
        let command = NSString(data: request.value, encoding: NSUTF8StringEncoding)!
        println("command received: " + command)
        let dateFormatter = NSDateFormatter()
        dateFormatter.dateStyle = NSDateFormatterStyle.NoStyle
        dateFormatter.timeStyle = NSDateFormatterStyle.MediumStyle
        let response = "\(command) (\(dateFormatter.stringFromDate(NSDate())))"
        println("response: " + response)
        peripheralManager.respondToRequest(request, withResult: CBATTError.Success)

        // wait before sending this
        let delayInSeconds = 0.1
        let startTime = dispatch_time(DISPATCH_TIME_NOW, Int64(delayInSeconds * Double(NSEC_PER_SEC)))
        dispatch_after(startTime, dispatch_get_main_queue()) { () -> () in
            let responseData = response.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)
            let didSendValue = self.peripheralManager.updateValue(responseData, forCharacteristic: self.responseCharacteristic, onSubscribedCentrals: nil)
            println("send response " + (didSendValue ? "ok" : "failed"))
        }
        
    }
    
}
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
    
    private var peripheralManager: CBPeripheralManager!
    // private var service: CBMutableService!
    private var isPoweredOn = false
    
    private let dechunker = Dechunker()
    
    private let chunkSize = 15
    private var pendingResponseChunks = Array< Array<UInt8> >()
    private var nChunks = 0
    private var nChunksSent = 0
    
    private var startTime = NSDate()

    
    // See:
    // http://stackoverflow.com/questions/24218581/need-self-to-set-all-constants-of-a-swift-class-in-init
    // http://stackoverflow.com/questions/24441254/how-to-pass-self-to-initializer-during-initialization-of-an-object-in-swift
    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    private func startService() {
        log("startService")
        peripheralManager.stopAdvertising()
        peripheralManager.removeAllServices()
        let service = CBMutableService(type: provisioningServiceUUID, primary: true)
        let commandCharacteristic = CBMutableCharacteristic(
            type: commandCharacteristicUUID,
            properties: CBCharacteristicProperties.Write,
            value: nil,
            permissions: CBAttributePermissions.Writeable)
        let responseCharacteristic = CBMutableCharacteristic(
            type: responseCharacteristicUUID,
            properties: CBCharacteristicProperties.Read,
            value: nil,
            permissions: CBAttributePermissions.Readable)
        service.characteristics = [commandCharacteristic, responseCharacteristic]
        peripheralManager.addService(service)
    }
    
    private func startAdvertising() {
        log("startAdvertising")
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
    
    private func processRequest(requestBytes: [UInt8]) {
        let request = NSString(bytes: requestBytes, length: requestBytes.count, encoding: NSUTF8StringEncoding)
        let response = "\(request!) [\(timestamp())]"
        // let response: String = request! as String
        var responseBytes = [UInt8]()
        for codeUnit in response.utf8 {
            responseBytes.append(codeUnit)
        }
        pendingResponseChunks = Chunker.makeChunks(responseBytes, chunkSize: chunkSize)
        nChunks = pendingResponseChunks.count
        nChunksSent = 0
        log("pending response \(responseBytes.count) bytes (\(nChunks) chunks of \(chunkSize) bytes)")
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
        log("peripheralManagerDidUpdateState \(caseString)")
        isPoweredOn = (peripheralManager.state == .PoweredOn)
        if isPoweredOn {
            startService()
        }
    }
    
    func peripheralManager(peripheral: CBPeripheralManager!, didAddService service: CBService!, error: NSError!) {
        var message = "peripheralManager didAddService \(nameFromUUID(service.UUID)) \(service.UUID) "
        if error == nil {
            message += "ok"
            log(message)
            startAdvertising()
        } else {
            message = "error " + error.localizedDescription
            log(message)
        }
    }
    
    func peripheralManagerDidStartAdvertising(peripheral: CBPeripheralManager!, error: NSError!) {
        var message = "peripheralManagerDidStartAdvertising "
        if error == nil {
            message += "ok"
        } else {
            message = "error " + error.localizedDescription
        }
        log(message)
    }
    
    func peripheralManager(peripheral: CBPeripheralManager!, didReceiveWriteRequests requests: [AnyObject]!) {
        log("peripheralManager didReceiveWriteRequests \(requests.count)")
        if requests.count == 0 {
            return
        }
        let request = requests[0] as! CBATTRequest
        
        log("request received (\(request.value.length) bytes)")
        
        var chunkBytes = [UInt8](count: request.value.length, repeatedValue: 0)
        request.value.getBytes(&chunkBytes, length: request.value.length)
        let retval = dechunker.addChunk(chunkBytes)
        if retval.isSuccess {
            if let finalResult = retval.finalResult {
                log("dechunker done")
                log("received \(finalResult.count) bytes from dechunker")
                processRequest(finalResult)
            } else {
                // chunk was ok, but more to come
                log("dechunker ok, but not done yet")
            }
            peripheralManager.respondToRequest(request, withResult: CBATTError.Success)
        } else {
            // chunk was faulty
            log("dechunker failed")
            peripheralManager.respondToRequest(request, withResult: CBATTError.UnlikelyError)
        }
    }
    
    func peripheralManager(peripheral: CBPeripheralManager!, didReceiveReadRequest request: CBATTRequest!) {
        let serviceUUID = request.characteristic.service.UUID
        let serviceName = nameFromUUID(serviceUUID)
        let characteristicUUID = request.characteristic.UUID
        let characteristicName = nameFromUUID(characteristicUUID)
        log("peripheralManager didReceiveReadRequest \(serviceName) \(characteristicName) \(serviceUUID) \(characteristicUUID)")
        if !pendingResponseChunks.isEmpty {
            if nChunksSent == 0 {
                startTime = NSDate()
            }
            let chunk = pendingResponseChunks[nChunksSent]
            let chunkData = NSData(bytes: chunk, length: chunk.count)
            nChunksSent++
            log("sending chunk \(nChunksSent)/\(nChunks) (\(chunkData.length) bytes)")
            request.value = chunkData
            peripheralManager.respondToRequest(request, withResult: CBATTError.Success)
            if nChunksSent == nChunks {
                let timeInterval = startTime.timeIntervalSinceNow
                log("all chunks sent in \(-timeInterval) secs")
                pendingResponseChunks.removeAll(keepCapacity: false)
                nChunks = 0
                nChunksSent = 0
            }
        } else {
            log("no pending response")
            peripheralManager.respondToRequest(request, withResult: CBATTError.RequestNotSupported)
        }
    }
    
}
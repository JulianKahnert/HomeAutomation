//
//  ConfigDTO.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 14.02.25.
//

import HAImplementations
import Vapor

extension ConfigDTO: @retroactive AsyncResponseEncodable {}
extension ConfigDTO: @retroactive AsyncRequestDecodable {}
extension ConfigDTO: @retroactive ResponseEncodable {}
extension ConfigDTO: @retroactive RequestDecodable {}
extension ConfigDTO: @retroactive Content {}

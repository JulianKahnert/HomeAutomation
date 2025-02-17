//
//  Job.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 16.02.25.
//

protocol Job: Sendable {
    func run() async
}

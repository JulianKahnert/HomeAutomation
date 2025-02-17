import Vapor

func routes(_ app: Application) throws {
    app.get { _ async in
        "It works!"
    }

    try app.register(collection: ConfigController())
}

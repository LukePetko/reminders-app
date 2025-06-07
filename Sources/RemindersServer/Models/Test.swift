import Fluent
import Vapor

final class Test: Model, Content, @unchecked Sendable {
    static let schema = "test"
    
    @ID(custom: "id", generatedBy: .database)
    var id: Int?
    
    @Field(key: "name")
    var name: String
    
    init() { }
    
    init(name: String) {
        self.name = name
    }
 }


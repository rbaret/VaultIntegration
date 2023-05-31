CREATE TABLE users(
  id INT NOT NULL AUTO_INCREMENT,
  name VARCHAR(255) NOT NULL,
  PRIMARY KEY (id)
);

INSERT INTO users (name) VALUES ('John Doe');
INSERT INTO users (name) VALUES ('Jane Doe');
INSERT INTO users (name) VALUES ('John Smith');
INSERT INTO users (name) VALUES ('Jane Smith');
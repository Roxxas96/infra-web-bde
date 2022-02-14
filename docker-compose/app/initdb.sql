--Create User Table

CREATE TABLE IF NOT EXISTS "User" (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) DEFAULT '',
    surname VARCHAR(50) DEFAULT '',
    pseudo VARCHAR(50) DEFAULT 'Anonym user',
    email VARCHAR(100) NOT NULL UNIQUE,
    password VARCHAR(200) NOT NULL CHECK (char_length(password) > 7),
    privilege INTEGER DEFAULT 0 CHECK (privilege = 0 OR privilege = 1 OR privilege = 2),
    wallet INTEGER DEFAULT 0
);

--Create Session table, sessions are used to authenticate user using a token put in "Athorization" header

CREATE TABLE IF NOT EXISTS "Session" (
    id SERIAL PRIMARY KEY,
    "userId" INTEGER NOT NULL,
    jwt VARCHAR(255) NOT NULL UNIQUE,
    CONSTRAINT "userSession" FOREIGN KEY ("userId") REFERENCES "User" ("id") ON DELETE CASCADE
);

--Create Challenge table

CREATE TABLE IF NOT EXISTS "Challenge" (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) DEFAULT 'Unnamed challenge',
    description TEXT DEFAULT '',
    reward INTEGER DEFAULT 0 CHECK (reward >= 0),
    "createdAt" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    "creatorId" INTEGER,
    CONSTRAINT "challengeCreator" FOREIGN KEY ("creatorId") REFERENCES "User" ("id") ON DELETE SET NULL
);

--Create Accomplishment table, accomplishments are sumbited by users and validated by admins to increase user wallet

CREATE TABLE If NOT EXISTS "Accomplishment" (
    id SERIAL PRIMARY KEY,
    "userId" INTEGER,
    "challengeId" INTEGER,
    proof TEXT DEFAULT '',
    "createdAt" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    validation INTEGER CHECK (validation = 1 OR validation = -1),
    CONSTRAINT "accomplishmentCreator" FOREIGN KEY ("userId") REFERENCES "User" ("id") ON DELETE SET NULL,
    CONSTRAINT "accomplishmentChallenge" FOREIGN KEY ("challengeId") REFERENCES "Challenge" ("id") ON DELETE SET NULL
);

--Create Goodies table

CREATE TABLE IF NOT EXISTS "Goodies" (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) DEFAULT 'Unnamed goodies',
    description TEXT DEFAULT '',
    image TEXT DEFAULT '',
    price INTEGER DEFAULT 0 CHECK (price >= 0),
    "buyLimit" INTEGER DEFAULT 1 CHECK ("buyLimit" >= 0),
    "createdAt" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    "creatorId" INTEGER,
    CONSTRAINT "goodiesCreator" FOREIGN KEY ("creatorId") REFERENCES "User" ("id") ON DELETE SET NULL
);

--Create Purchase table, purchases are traces of what a user has bought

CREATE TABLE IF NOT EXISTS "Purchase" (
    id SERIAL PRIMARY KEY,
    "goodiesId" INTEGER NOT NULL,
    "userId" INTEGER NOT NULL,
    "createdAt" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

--Insert a default Super admin so you can add other admins

INSERT INTO "User" (pseudo, email, password, privilege) VALUES (
    'Admin user',
    'admin@umontpellier.fr',
    '$2b$10$HtOLm9x.vZEPe672Kan3pueDmH5LaBpPV2kOiEWtE4xdA3pRfNP/e',
    2
);

--On validation trigger, update user wallet when his accomplishment has been validated by an admin, validation states are Accepted: 1, Refused: -1

CREATE OR REPLACE FUNCTION on_validation_update()
  RETURNS TRIGGER 
  LANGUAGE PLPGSQL
  AS
$$
DECLARE
	gain INTEGER;
BEGIN
    IF NEW."challengeId" IS NULL OR NEW."userId" IS NULL THEN
        RETURN NEW;
    END IF;
    IF OLD.validation = 1 OR OLD.validation = -1 THEN
        RAISE EXCEPTION 'Accomplishment has allready a validation state';
    END IF;
	IF NEW.validation = 1 THEN
        SELECT reward INTO gain FROM "Challenge" WHERE id = NEW."challengeId";

		UPDATE "User" SET wallet = wallet + gain WHERE id = NEW."userId";
	END IF;

	RETURN NEW;
END;
$$;

--Use trigger on each update on table accomplishment

CREATE OR REPLACE TRIGGER increase_wallet
    BEFORE UPDATE
    ON "Accomplishment"
    FOR EACH ROW
    EXECUTE PROCEDURE on_validation_update();

--On purchase trigger, update user wallet on buying a goodies

CREATE OR REPLACE FUNCTION on_purchase()
  RETURNS TRIGGER 
  LANGUAGE PLPGSQL
  AS
$$
DECLARE
	cost INTEGER;
    bank INTEGER;
    bought_count INTEGER;
    bought_limit INTEGER;
BEGIN
    SELECT price, "buyLimit" INTO cost, bought_limit FROM "Goodies" WHERE id = NEW."goodiesId";
    SELECT wallet INTO bank FROM "User" WHERE id = NEW."userId";
    SELECT count(p.id) INTO bought_count FROM "Purchase" p INNER JOIN "Goodies" g ON g.id = p."goodiesId" WHERE p."userId" = NEW."userId";

    IF bought_count >= bought_limit THEN
        RAISE EXCEPTION 'Limit reached';
    END IF;

    IF cost > bank THEN
        RAISE EXCEPTION 'Not enought money in wallet';
    END IF;

    UPDATE "User" SET wallet = wallet - cost WHERE id = NEW."userId";

	RETURN NEW;
END;
$$;

--Use trigger on each insert on table purchase

CREATE OR REPLACE TRIGGER decrease_wallet
    BEFORE INSERT
    ON "Purchase"
    FOR EACH ROW
    EXECUTE PROCEDURE on_purchase();

--On refund trigger, update user wallet when an admin delete his purchase
CREATE OR REPLACE FUNCTION on_refund()
  RETURNS TRIGGER 
  LANGUAGE PLPGSQL
  AS
$$
DECLARE
	cost INTEGER;
BEGIN
    SELECT price INTO cost FROM "Goodies" WHERE id = OLD."goodiesId";

    UPDATE "User" SET wallet = wallet + cost WHERE id = OLD."userId";

	RETURN OLD;
END;
$$;

--Use trigger on each delete on table purchase

CREATE OR REPLACE TRIGGER increase_wallet
    BEFORE DELETE
    ON "Purchase"
    FOR EACH ROW
    EXECUTE PROCEDURE on_refund();
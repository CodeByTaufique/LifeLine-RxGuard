#!/bin/bash

# DataBase files to access them with short names
DB="./lifeLineData"
MEDS="$DB/medsInventory.txt"
BLOOD="$DB/bloodInventory.txt"
USER="$DB/systemUsers.txt"
LOG="$DB/auditTrail.txt"
BILL="$DB/patientBills.txt"
DONOR="$DB/donorDetails.txt"
BACKUP="$DB/backUps"
EMERGENCY="$DB/.activeEmergerncy"

# Mark active User as we have Pharpacist & Staff
activeUser=""
activeRole=""

# This will keep track of all things happens in the system
writeLog() {
    	local category="$1"
    	local message="$2"
    	echo "$(date '+%Y-%m-%d %H:%M:%S') | [$category] | User: $activeUser | $message" >> "$LOG"
}

# Setting DataBase so that if not exixt it creates one or load the previous one
dataBase() {
        if [ ! -d "$DB" ]; then
                mkdir -p "$DB"
        fi
        mkdir -p "$BACKUP"

        for file in "$MEDS" "$BLOOD" "$USER" "$LOG" "$BILL" "$DONOR"; do
                if [ ! -f "$file" ]; then
                        touch "$file"
                fi
        done
}

# This hepls wwhen billing is called
signature() {
        sigText=""
        issued=$(grep -i "Issued .* to Patient: $patient$" "$LOG")

        while read -r line; do
                qty=$(echo "$line" | sed -n 's/.*Issued \([0-9]\+\) units.*/\1/p')
                med=$(echo "$line" | sed -n 's/.*units of \(.*\) to Patient.*/\1/p')

                sigText="$sigText
		Patient:$patient | Med:$med | Qty:$qty | IssuedBy:$activeUser"
        done <<< "$issued"
}

# Check the expiry status for the meds
expiryStatus() {
        local targetDate="$1"
        local currentTime=$(date +%s)
        local expiryDate=$(date -d "$targetDate" +%s)

        if [ -z "$expiryDate" ]; then
                echo "UNKNOWN"
                return
        fi

        local secDiff=$(( expiryDate - currentTime ))
        local dayDiff=$(( secDiff / 86400 ))

        if [ "$dayDiff" -lt 0 ]; then
                echo "EXPIRED"
        elif [ "$dayDiff" -le 7 ]; then
                echo "CRITICAL"
        else
                echo "SAFE"
        fi
}

# Check and alert the low stock of any meds
lowStock() {
        local alertMsg=""
        while IFS='|' read -r name qty price exp rest; do
                if [ -n "$qty" ] && [ "$qty" -lt 5 ]; then
                        alertMsg="${alertMsg}Item: $name (Remaining : $qty)\n"
                fi
        done < "$MEDS"
        if [ -n "$alertMsg" ]; then
                zenity --warning --title="Low Stock Alert!" \
                        --text="The following items are Low : \n\n$alertMsg"
        fi
}

#Add meds to the inventory
addMeds() {
        input=$(zenity --forms --title="Inventory Entry" --text="Register Medicine Stock" \
                --add-entry="Medicine Name" \
                --add-entry="Category (e.g. Antibiotic / Painkiller / Syrup)" \
                --add-entry="Quantity (Units)" \
                --add-entry="Price (Per Unit)" \
                --add-calendar="Expiry Date" \
                --add-list="Requires Permission?" --list-values="No|Yes")

        if [ -z "$input" ]; then
			return
		fi

        input=$(echo "$input" | tr -d '\r\n')
        medsName=$(echo "$input" | cut -d '|' -f1)
        medsCat=$(echo "$input" | cut -d '|' -f2)
        medsQty=$(echo "$input" | cut -d '|' -f3)
        medsPrice=$(echo "$input" | cut -d '|' -f4)
        medsExp=$(echo "$input" | cut -d '|' -f5)
        medsRest=$(echo "$input" | cut -d '|' -f6)

        if [[ -z "$medsQty" || ! "$medsQty" =~ ^[0-9]+$ ]]; then
                zenity --error --text="Invalid Quantity!"
                return
        fi

        if grep -qi "^$medsName|" "$MEDS"; then
                oldLine=$(grep -i "^$medsName|" "$MEDS")

                oldCat=$(echo "$oldLine" | cut -d '|' -f2)
                oldQty=$(echo "$oldLine" | cut -d '|' -f3)
                oldPrice=$(echo "$oldLine" | cut -d '|' -f4)
                oldRest=$(echo "$oldLine" | cut -d '|' -f6)

                newQty=$((oldQty + medsQty))

                grep -vi "^$medsName|" "$MEDS" > "$MEDS.tmp"
                echo "$medsName|$oldCat|$newQty|$oldPrice|$medsExp|$oldRest" >> "$MEDS.tmp"
                mv "$MEDS.tmp" "$MEDS"

                writeLog "PHARMACY" "Inventory Updated : $medsName ($oldCat), Added Qty: $medsQty, Total: $newQty"
                zenity --info --text="$medsName already exists.\n\nQuantity updated to $newQty\nExpiry replaced."

        else
                echo "$medsName|$medsCat|$medsQty|$medsPrice|$medsExp|$medsRest" >> "$MEDS"
                writeLog "PHARMACY" "Inventory Addition : $medsName ($medsCat), Qty: $medsQty"
                zenity --info --text="Successfully Registered $medsName in the Pharmacy!"
        fi
}

# Add new Blood Donors
manageDonors() {
    	donorInput=$(zenity --forms --title="Donor Management" --text="Add Donor Details" \
         	   --add-entry="Full Name" \
          	  --add-list="Blood Type" --list-values="A+|A-|B+|B-|O+|O-|AB+|AB-" \
          	  --add-entry="Phone Number" \
           	 --add-calendar="Registration Date")

    	if [ -n "$donorInput" ]; then
        	echo "$donorInput" >> "$DONOR"
        	bloodType=$(echo "$donorInput" | cut -d '|' -f2 | tr -d ',')
        	found=0
      		tempFile="blood_temp.txt" > "$tempFile"

        	if [ -f "$BLOOD" ]; then
            	while IFS='|' read -r type count || [ -n "$type" ]; do
                	if [ "$type" = "$bloodType" ]; then
                    	count=$((count + 1))
                    	found=1
                	fi
                echo "$type|$count" >> "$tempFile"
            	done < "$BLOOD"
        	fi

        	if [ $found -eq 0 ]; then
            	echo "$bloodType|1" >> "$tempFile"
        	fi
        	mv "$tempFile" "$BLOOD"
        	writeLog "DONOR" "Registered Donor : $(echo "$donorInput" | cut -d '|' -f1)"
        	zenity --info --text="Donor Details Saved Successfully!"
    	fi
}

# Generates the bills for the patient
generateBill() {
        choice=$(zenity --list --title="Billing Options" \
                --column="Action" \
                "Manual Invoice" \
                "Generate from Issued Medicines")

        if [ -z "$choice" ]; then
		 	return
		fi

        if [ "$choice" = "Manual Invoice" ]; then

                billInput=$(zenity --forms --title="Financial Billing" --text="Invoice" \
			--width=550 --height=550 \
                        --add-entry="Patient Name" \
                        --add-list="Type" --list-values="Service|Medicine" \
                        --add-entry="Amount")

                if [ -n "$billInput" ]; then
                        echo "$(date +%F)|$billInput" >> "$BILL"
                        writeLog "BILLING" "Invoiced : $(echo "$billInput" | cut -d '|' -f1)"
                        zenity --info --text="Invoice Generated and Archived!"
                fi
        else
                patient=$(zenity --entry --title="Search Patient" \
                        --text="Enter Patient Name for Billing")

                if [ -z "$patient" ]; then
			 return
		fi

                issued=$(grep -i "Issued .* to Patient: $patient$" "$LOG")

                if [ -z "$issued" ]; then
                        zenity --error --text="No issued medicines found for $patient"
                        return
                fi

                total=0
                details=""
                while read -r line; do
                        qty=$(echo "$line" | sed -n 's/.*Issued \([0-9]\+\) units.*/\1/p')
                        med=$(echo "$line" | sed -n 's/.*units of \([^ (]*\).*/\1/p')
                        price=$(grep "^$med|" "$MEDS" | cut -d '|' -f4)

                        if [ -z "$price" ]; then
				continue
			fi

                        cost=$((qty * price))
                        total=$((total + cost))
                        details="$details\n$med x$qty = $cost"

                done <<< "$issued"
		signature

		zenity --info \
        	--title="Auto Generated Bill" \
        	--width=700 \
        	--height=600 \
        	--no-wrap \
        	--text="Patient: $patient
Issued Medicines:
$details
Signature:
$sigText
Total Amount: $total"

echo "$(date +%F)|$patient|Medicine|$total" >> "$BILL"
                writeLog "BILLING" "Auto bill generated for Patient: $patient | Amount: $total"
        fi
}

# This just check that all required files of this system is present
healthCheck() {
        healthReport=""
        for file in "$MEDS" "$BLOOD" "$USER" "$LOG"; do
                if [ -f "$file" ]; then
                        healthReport="${healthReport} $file: Online\n"
                else
                        healthReport="${healthReport} $file: Missing\n"
                fi
        done
        zenity --info --title="System Status!" --text="Health Check Report : \n\n$healthReport" \
			--width=550 --height=550
}

# This is for viewing the meds in inventory
viewInventory() {
		(
        	count=1
        	while IFS='|' read -r name category qty price exp rest || [ -n "$name" ]; do
            		risk=$(expiryStatus "$exp" | tr -d '\n')
            		if [ -z "$risk" ]; then
				 risk="$exp"
			fi
        	        echo "$count. $name | $category | Stock: $qty | Price: $price | $risk | $rest"
           		count=$((count + 1))
        	done < "$MEDS"
    	) | zenity --list \
        	--title="Pharmacy Medicine Inventory" \
        	--width=650 \
        	--height=500 \
        	--column="Available Medicines"
}

# To check the Blood inventory
viewBloodInventory() {
        getCount() {
                count=$(grep "^$1|" "$BLOOD" | cut -d '|' -f2)
                echo "${count:-0}"
        }

        (
                echo "A+ : $(getCount A+)"
                echo "A- : $(getCount A-)"
                echo "B+ : $(getCount B+)"
                echo "B- : $(getCount B-)"
                echo "O+ : $(getCount O+)"
                echo "O- : $(getCount O-)"
                echo "AB+ : $(getCount AB+)"
                echo "AB- : $(getCount AB-)"
        ) | zenity --list \
                --title="Available Blood Inventory" \
                --width=550 \
                --height=550 \
                --column="Blood Availability"
}

# Check meds expire so that staff accediently dont issue expired meds
isExpired() {
        line=$(grep -i "^$1|" "$MEDS")
 
        if [ -z "$line" ]; then
                return
        fi

        expDate=$(echo "$line" | cut -d '|' -f5)
 
        today=$(date +%F)

        if [[ "$expDate" < "$today" ]]; then
                zenity --error --text="Medicine Expired!\n\nExpiry Date: $expDate"
                writeLog "WARNING" "Expired medicine access blocked: $1"
                expiredFlag=1
                return
        fi
 
        expiredFlag=0
        return
}


# Issue meds for the patient by the staff
issueMeds() {
        target=$(zenity --entry --title="Issue Item" --text="Enter name of the Medicine or Blood (e.g., A+):")
        if [ -z "$target" ]; then
                return
        fi

        # Check if target is a medicine
        line=$(grep -i "^$target|" "$MEDS")
        if [ -n "$line" ]; then
                n=$(echo "$line" | cut -d '|' -f1)
                cat=$(echo "$line" | cut -d '|' -f2)
                q=$(echo "$line" | cut -d '|' -f3)
                r=$(echo "$line" | cut -d '|' -f6)
				
				expiredFlag=0
                isExpired "$n"

                if [ "$expiredFlag" -eq 1 ]; then
                        return
                fi

                if [ "$r" == "Yes" ] && [ "$activeRole" != "Pharmacist" ]; then
                        zenity --warning --text="Access Denied!\n\n$n is Restricted.\nRequest Pharmacist for this Medicine!"
                        writeLog "SECURITY" "Access Denied: $n requested by $activeUser"
                        return
                fi
                patientName=$(zenity --entry --title="Patient Information" --text="Enter Patient Name:")
                if [ -z "$patientName" ]; then
                        zenity --error --text="Patient Name is required to issue medication!"
                        return
                fi
                askQty=$(zenity --entry --text="Quantity to issue (Available $q) : ")
                if [[ "$askQty" =~ ^[0-9]+$ ]] && [ "$askQty" -le "$q" ] && [ "$askQty" -gt 0 ]; then
                        remaining=$((q - askQty))
                        grep -v "^$n|" "$MEDS" > "$MEDS.tmp"
                        cat=$(echo "$line" | cut -d '|' -f2)
                        price=$(echo "$line" | cut -d '|' -f4)
                        exp=$(echo "$line" | cut -d '|' -f5)
                        rest=$(echo "$line" | cut -d '|' -f6)
                        echo "$n|$cat|$remaining|$price|$exp|$rest" >> "$MEDS.tmp"
                        mv "$MEDS.tmp" "$MEDS"
                        writeLog "ISSUE" "Issued $askQty units of $n ($cat) to Patient: $patientName"
                        zenity --info --text="Transaction Approved!\n\nItem: $n\nQty: $askQty\nPatient: $patientName\nInventory Updated."
                else
                        zenity --error --text="Insufficient Stock or Invalid Quantity!"
                fi

        else
                target=$(echo "$target" | tr -d ',[:space:]')
                line=$(grep -i "^$target|" "$BLOOD")
                if [ -z "$line" ]; then
                        zenity --error --text="Error: '$target' not found in Medicines or Blood Inventory!"
                        return 
                fi
                bloodType=$(echo "$line" | cut -d '|' -f1)
                qty=$(echo "$line" | cut -d '|' -f2)
                patientName=$(zenity --entry --title="Patient Information" --text="Enter Patient Name for Blood:")
                if [ -z "$patientName" ]; then
                        zenity --error --text="Patient Name is required to issue blood!"
                        return 
                fi
                askQty=$(zenity --entry --text="Units to issue (Stock $qty) : ")
                if [[ "$askQty" =~ ^[0-9]+$ ]] && [ "$askQty" -le "$qty" ] && [ "$askQty" -gt 0 ]; then
                        remaining=$((qty - askQty))
                        grep -v "^$bloodType|" "$BLOOD" > "$BLOOD.tmp"
                        echo "$bloodType|$remaining" >> "$BLOOD.tmp"
                        mv "$BLOOD.tmp" "$BLOOD"
                        writeLog "ISSUE" "Issued $askQty units of blood $bloodType to Patient: $patientName"
                        zenity --info --text="Blood Issued Successfully!\n\nBlood Type: $bloodType\nQty: $askQty\nPatient: $patientName\nInventory Updated."
                else
                        zenity --error --text="Insufficient Blood Stock or Invalid Quantity!"
                fi
        fi
}

# To handle request for the restricted meds
requestMeds() {
        med=$(zenity --entry --title="Request Restricted Medicine" \
                --text="Enter Restricted Medicine Name:")
        if [ -z "$med" ]; then
		 	return
		fi

        line=$(grep -i "^$med|" "$MEDS")
        if [ -z "$line" ]; then
                zenity --error --text="Medicine not found!"
                return
        fi
		
		expiredFlag=0
        isExpired "$n"
        if [ "$expiredFlag" -eq 1 ]; then
                return
        fi
		
        restriction=$(echo "$line" | cut -d '|' -f6)
        if [ "$restriction" != "Yes" ]; then
                zenity --info --text="Medicine is not restricted."
                return
        fi

        patient=$(zenity --entry --title="Patient Name" \
                --text="Enter Patient Name:")
        if [ -z "$patient" ]; then
			return
		fi

        qty=$(zenity --entry --title="Quantity" --text="Enter Quantity:")
        if [[ ! "$qty" =~ ^[0-9]+$ ]]; then
			return
		fi

        echo "$(date +%F)|$activeUser|$patient|$med|$qty|DENIED" >> "$EMERGENCY"
        writeLog "REQUEST" \
                "Restricted medicine requested: $med Qty:$qty Patient:$patient Status:DENIED"
        zenity --info --text="Request submitted.\nWaiting for pharmacist approval."
}

# Response of the restricted meds --> this is for Pharmacist
respondReq() {
        while true; do
                req=$(grep '|DENIED$' "$EMERGENCY" | head -n 1)
                if [ -z "$req" ]; then
                        zenity --info --title="Requests" \
                                --text="No pending restricted medicine requests."
                        break
                fi

                date=$(echo "$req" | cut -d '|' -f1)
                staff=$(echo "$req" | cut -d '|' -f2)
                patient=$(echo "$req" | cut -d '|' -f3)
                med=$(echo "$req" | cut -d '|' -f4)
                qty=$(echo "$req" | cut -d '|' -f5)

                zenity --question --title="Restricted Medicine Request" \
			--width=450 --height=350 \
                        --text="Date      : $date
Requested : $staff
Patient   : $patient
Medicine  : $med
Quantity  : $qty

Approve and ISSUE this medicine?" \
                        --ok-label="ACCEPT & ISSUE" \
                        --cancel-label="DENY"
		                decision=$?

                grep -v "^$req$" "$EMERGENCY" > "$EMERGENCY.tmp"
                if [ "$decision" -eq 0 ]; then
                        line=$(grep -i "^$med|" "$MEDS")
                        if [ -z "$line" ]; then
                                zenity --error --text="Medicine not found in inventory!"
                                echo "$req" >> "$EMERGENCY.tmp"
                        else
                                stock=$(echo "$line" | cut -d '|' -f3)
                                if [ "$qty" -gt "$stock" ]; then
                                        zenity --error --text="Insufficient stock to issue!"
                                        echo "$req" >> "$EMERGENCY.tmp"
                                else
                                        remaining=$((stock - qty))
                                        grep -v "^$med|" "$MEDS" > "$MEDS.tmp"
                                        cate=$(echo "$line" | cut -d '|' -f2)
					price=$(echo "$line" | cut -d '|' -f4)
					exp=$(echo "$line" | cut -d '|' -f5)
					rest=$(echo "$line" | cut -d '|' -f6)
					echo "$med|$cat|$remaining|$price|$exp|$rest" >> "$MEDS.tmp"
                                        mv "$MEDS.tmp" "$MEDS"
                                        echo "$date|$staff|$patient|$med|$qty|ISSUED" >> "$EMERGENCY.tmp"

                                        writeLog "ISSUE" \
                                                "Issued $qty units of $med (Category : $cate) to Patient: $patient"

                                        zenity --info --text="Medicine ISSUED successfully!"
                                fi
                        fi
                else
                        echo "$date|$staff|$patient|$med|$qty|REJECTED" >> "$EMERGENCY.tmp"
                        writeLog "PHARMACY" \
                                "Restricted request REJECTED: $med Qty:$qty Patient:$patient"
                        zenity --warning --text="Request rejected."
                fi
                mv "$EMERGENCY.tmp" "$EMERGENCY"

                zenity --text-info --title="Emergency Request History" \
                        --width=600 --height=400 \
                        --filename="$EMERGENCY"
        done
}

# Search in the log file to find desired activity or meds usage
searchLog() {
        keyword=$(zenity --entry --title="Search Logs" --text="Enter Keyword (Name/Date/Action) : ")
        if [ -z "$keyword" ]; then
                return
        fi

        results=$(grep -i "$keyword" "$LOG")
        if [ -n "$results" ]; then
                echo "$results" | zenity --text-info --title="Search Results" --width=800 --height=500
        else
                zenity --info --text="No Matching Logs found for '$keyword'."
        fi
}

# As name says this make a staff register but only admin can make it
registerAccount() {
        role=$(zenity --list \
                --title="Select Account Type" \
                --column="Role" \
                "User" \
                "Pharmacist")

        if [ -z "$role" ]; then
			return
		fi

        regData=$(zenity --forms --title="Create Account ($role)" \
                --add-entry="Enter Username : " \
                --add-password="Create a Password : " \
                --add-password="Confirm Password : ")

        if [ -z "$regData" ]; then
			return
		fi

        u=$(echo "$regData" | cut -d '|' -f1)
        p1=$(echo "$regData" | cut -d '|' -f2)
        p2=$(echo "$regData" | cut -d '|' -f3)
        if [[ -z "$u" || -z "$p1" || "$p1" != "$p2" ]]; then
                zenity --error --text="Validation Failed! Password mismatch or empty fields."
                return
        fi

        if grep -q "^$u|" "$USER"; then
                zenity --error --text="Username already exists!"
                return
        fi

        echo "$u|$p1|$role" >> "$USER"

        zenity --info --text="Account Created Successfully!\n\nUser: $u\nRole: $role"
        writeLog "USER ADDITION" "New $role Account Created: $u"
}

# This make the staff to change their password as admin create their password 1st time
changeUserPass() {
        newPass=$(zenity --password --title="Update Password" --text="Enter New Password : ")
        if [ -n "$newPass" ]; then
                nowRole=$(grep "^$activeUser|" "$USER" | cut -d '|' -f3)
                grep -v "^$activeUser|" "$USER" > "$USER.tmp"
                echo "$activeUser|$newPass|$nowRole" >> "$USER.tmp"
                mv "$USER.tmp" "$USER"
                zenity --info --text="Password Updated Successfully!"
                writeLog "AUTHENTICATION" "User Updated Their Password!"
        fi
}

# This is the menu where pharmacist Oparates
pharmaMenu() {
        lowStock
        while true; do
		if grep -q '|DENIED$' "$EMERGENCY"; then
                        reqStatus="🔴 EMERGENCY REQUEST PENDING"
                else
                        reqStatus="🟢 NO PENDING REQUESTS"
                fi
                choice=$(zenity --list --title="Pharmacist Dashboard" --text="$reqStatus"  --width=500 --height=600 \
                        --column="CMD" --column="Service Description" \
                        "1. ADD" "Register New Medicine to the Inventory" \
                        "2. BLOOD" "Manage Blood Bank Units" \
                        "3. DONORS" "Donor Registration & Records" \
                        "4. BILL" "Patient Billing & Invoices" \
                        "5. STATUS" "Perform System Health Check" \
                        "6. EMERGENCY" "Request for the Medicine" \
                        "7. USERS" "Manage Staff Access & Roles" \
                        "8. SEARCH" "Search Activity & Audit Logs" \
                        "9. BACKUPS" "Export Database Backups" \
                        "10. UPDATE PASSWORD" "Change User Password" \
                        "11. LOGOUT" "End Current Session")

                case "$choice" in 
                        "1. ADD") addMeds ;;
                        "2. BLOOD") viewBloodInventory ;;
                        "3. DONORS") manageDonors ;;
                        "4. BILL") generateBill ;;
                        "5. STATUS") healthCheck ;;
                        "6. EMERGENCY") respondReq ;;
                        "7. USERS") registerAccount "User" ;;
                        "8. SEARCH") searchLog ;;
                        "9. BACKUPS")
                                zip -r "$BACKUP/dbBackup$(date +%s).zip" "$DB" > /dev/null 2>&1
                                zenity --info --text="Backup saved in $BACKUP"
                                ;;
                        "10. UPDATE PASSWORD") changeUserPass ;;
                        "11. LOGOUT") break ;;
                        *) break ;;
                esac
        done
}

# Staff menu where Stuff oparates
staffMenu() {
        while true; do
                choice=$(zenity --list --title="STAFF Portal - $activeUser" --width=450 --height=450 \
                        --column="CMD" --column="Hospital Service" \
                        "1. VIEW" "Check Current Pharmacy Stock" \
                        "2. ISSUE" "Request & Issue Medicine" \
                        "3. BLOOD" "Check Blood Bank Levels" \
                        "4. DONORS" "View Donor Contact List" \
						"5. REQUEST MEDICINE" "Restricted Medcine Request" \
                        "6. FINANCE" "Check Patient Bill History" \
                        "7. SEARCH" "Search Past Activities" \
                        "8. UPDATE PASS" "Change Password" \
                        "9. LOGOUT" "Exit Portal")

                case "$choice" in
                        "1. VIEW") viewInventory ;;
                        "2. ISSUE") issueMeds ;;
                        "3. BLOOD") viewBloodInventory ;;
                        "4. DONORS")
								if [ ! -s "$DONOR" ]; then
	    							zenity --info --text="No donors registered yet."
    								return
								fi
								donorList=()
								while IFS='|' read -r name blood phone date
								do
    								donorList+=("$name | $blood | $phone | $date")
								done < "$DONOR"
								zenity --list \
       								--title="Registered Donors" \
       								--width=650 \
       								--height=500 \
       								--column="Available Donors" \
       							"${donorList[@]}"
								;;
						"5. REQUEST MEDICINE") requestMeds ;;
                        "6. FINANCE")
								if [ ! -s "$BILL" ]; then
    								zenity --info --text="No billing records yet."
    								return
								fi
								billList=()
								
								while IFS='|' read -r date patient type amount
								do
    								billList+=("$date | $patient | $type | $amount")
								done < "$BILL"
								zenity --list \
				       				--title="Billing Logs" \
				       				--width=700 \
				       				--height=500 \
				       				--column="Billing Records" \
       							"${billList[@]}"
								;;
                        "7. SEARCH") searchLog ;;
                        "8. UPDATE PASS") changeUserPass ;;
                        "9. LOGOUT") break ;;
                        *) break ;;
                esac
        done
}

# Minn method which run 1st then rely to the other methodes
lifeLine() {
        dataBase
        if [ ! -s "$USER" ]; then
                zenity --info --text="First Time Setup : Register as the Admin Pharmacist!"
                registerAccount "Pharmacist"
        fi

        while true; do
                loginRaw=$(zenity --forms --title="LifeLine Login" --text="System Authentication" \
                                --add-entry="Username" \
                                --add-password="Password")
                if [ -z "$loginRaw" ]; then
                        exit 0
                fi

                uLog=$(echo "$loginRaw" | cut -d'|' -f1)
                pLog=$(echo "$loginRaw" | cut -d'|' -f2)
                match=$(grep "^$uLog|$pLog|" "$USER")

                if [ -n "$match" ]; then
                        activeUser="$uLog"
                        activeRole=$(echo "$match" | cut -d'|' -f3)
                        writeLog "AUTHENTICATION" "Successful Login"
                        if [ "$activeRole" == "Pharmacist" ]; then
                                pharmaMenu
                        else
                                staffMenu
                        fi
                else
                        zenity --error --text="Access Denied! Invalid Credentials!"
                        writeLog "AUTHENTICATION" "Failed Login Attempt : $uLog"
                fi
        done
}

# Call the main method
lifeLine
